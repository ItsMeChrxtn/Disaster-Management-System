<?php
namespace App\Controllers;

use App\Core\{Request, Response, Validator};
use App\Models\{CoordinationMessage, Notification};

/** PDRRMO (admin) <-> MDRRMO/CDRRMO (municipal sub-admin) coordination channel. */
final class CoordinationController
{
    public function channels(Request $r): never
    {
        $model=new CoordinationMessage();$admin=$r->user['role']==='admin';
        $channels=$model->channels((int)$r->user['id'],$r->user['role'],$admin?null:(int)$r->user['municipality_id']);
        Response::success(['role'=>$r->user['role'],'office'=>$admin?'PDRRMO':CoordinationMessage::officeFor($r->user['municipality_name']??null),'channels'=>$channels]);
    }

    public function messages(Request $r): never
    {
        $model=new CoordinationMessage();
        if($r->user['role']==='admin'&&$r->query('municipality_id')==='all')Response::success(['municipality_id'=>null,'messages'=>$model->broadcasts()]);
        $mid=$this->channelId($r);
        $model->markChannelRead((int)$r->user['id'],$mid);
        Response::success(['municipality_id'=>$mid,'messages'=>$model->thread($mid)]);
    }

    public function store(Request $r): never
    {
        $d=$r->body();Validator::require($d,['subject','body']);$errors=[];
        $subject=trim((string)$d['subject']);$body=trim((string)$d['body']);$category=(string)($d['category']??'general');$priority=(string)($d['priority']??'normal');
        if(mb_strlen($subject)<2||mb_strlen($subject)>180)$errors['subject']='Must contain 2 to 180 characters';
        if($body===''||mb_strlen($body)>5000)$errors['body']='Required and must not exceed 5000 characters';
        if(!in_array($category,CoordinationMessage::CATEGORIES,true))$errors['category']='Select a supported category';
        if(!in_array($priority,CoordinationMessage::PRIORITIES,true))$errors['priority']='Select a supported priority';
        $data=['subject'=>$subject,'body'=>$body,'category'=>$category,'priority'=>$priority,'requires_ack'=>false];
        $model=new CoordinationMessage();$notifications=new Notification();$ids=[];
        $label=strtoupper($priority)==='NORMAL'?'':'['.strtoupper($priority).'] ';

        if($r->user['role']==='admin'){
            $data['requires_ack']=filter_var($d['requires_ack']??false,FILTER_VALIDATE_BOOLEAN);
            $targets=$d['municipality_ids']??($d['municipality_id']??null);
            if($targets==='all'||$targets===['all']){
                if($errors)Response::error('Validation failed',422,$errors);
                $ids[]=$model->create(null,(int)$r->user['id'],'to_lgu',$data);
                $notifications->notifyRole('subadmin',null,'announcement',$label.'PDRRMO: '.$subject,mb_substr($body,0,400));
            }else{
                $targets=array_values(array_unique(array_filter(array_map('intval',(array)$targets))));
                $valid=$model->activeMunicipalities($targets);
                if(!$targets||count($valid)!==count($targets))$errors['municipality_ids']='Select at least one active municipality';
                if($errors)Response::error('Validation failed',422,$errors);
                foreach($valid as $mid=>$name){$ids[]=$model->create((int)$mid,(int)$r->user['id'],'to_lgu',$data);$notifications->notifyRole('subadmin',(int)$mid,'announcement',$label.'PDRRMO: '.$subject,mb_substr($body,0,400));}
            }
        }else{
            if($errors)Response::error('Validation failed',422,$errors);
            $mid=(int)$r->user['municipality_id'];if(!$mid)Response::error('Your account is not assigned to a municipality',422);
            $ids[]=$model->create($mid,(int)$r->user['id'],'to_province',$data);
            $office=CoordinationMessage::officeFor($r->user['municipality_name']??null);
            $notifications->notifyRole('admin',null,'announcement',$label.$office.' '.($r->user['municipality_name']??'').': '.$subject,mb_substr($body,0,400));
        }
        Response::success(['ids'=>$ids,'message'=>count($ids)===1?'Message sent':count($ids).' messages sent'],201);
    }

    public function acknowledge(Request $r): never
    {
        $model=new CoordinationMessage();$item=$model->find((int)$r->params['id']);if(!$item)Response::error('Message not found',404);
        $mid=(int)$r->user['municipality_id'];
        if($item['direction']!=='to_lgu'||($item['municipality_id']!==null&&(int)$item['municipality_id']!==$mid))Response::error('Only the receiving municipality can acknowledge this message',403);
        $model->acknowledge((int)$item['id'],$mid,(int)$r->user['id']);
        $office=CoordinationMessage::officeFor($r->user['municipality_name']??null);
        (new Notification())->notifyRole('admin',null,'announcement',$office.' '.($r->user['municipality_name']??'').' acknowledged',$item['subject']);
        Response::success(['message'=>'Acknowledged']);
    }

    private function channelId(Request $r): int
    {
        if($r->user['role']!=='admin'){$mid=(int)$r->user['municipality_id'];if(!$mid)Response::error('Your account is not assigned to a municipality',422);return $mid;}
        $mid=filter_var($r->query('municipality_id'),FILTER_VALIDATE_INT,['options'=>['min_range'=>1]]);if($mid===false)Response::error('Select a municipality channel',422);
        if(!(new CoordinationMessage())->activeMunicipalities([$mid]))Response::error('Municipality not found',404);
        return (int)$mid;
    }
}
