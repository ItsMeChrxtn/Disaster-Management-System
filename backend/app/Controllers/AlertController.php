<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\Alert;

final class AlertController
{
    private const TYPES=['weather_alert','flood_alert','earthquake_alert','storm_surge_alert','emergency_alert'];
    private const LEVELS=['info','advisory','warning','critical'];
    public function index(Request $r): never { Response::success((new Alert())->publicSent()); }
    public function manage(Request $r): never { Response::success((new Alert())->managed($r->user['role']==='subadmin'?(int)$r->user['municipality_id']:null)); }
    public function show(Request $r): never { $item=$this->findOrFail((int)$r->params['id']);$this->assertScope($r,$item);Response::success($item); }
    public function store(Request $r): never { $data=$this->validated($r);$model=new Alert();$id=$model->create($data,(int)$r->user['id']);Response::success($model->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$item=$this->findOrFail($id);$this->assertScope($r,$item);if($item['status']==='deleted')Response::error('Deleted alerts cannot be edited',422);$model=new Alert();$model->update($id,$this->validated($r));Response::success($model->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$item=$this->findOrFail($id);$this->assertScope($r,$item);(new Alert())->setStatus($id,'deleted');Response::success(['message'=>'Alert deleted']); }
    public function send(Request $r): never { $id=(int)$r->params['id'];$item=$this->findOrFail($id);$this->assertScope($r,$item);if($item['status']==='deleted')Response::error('Deleted alerts cannot be sent',422);(new Alert())->setStatus($id,'sent');Response::success(['message'=>'Alert sent','alert'=>(new Alert())->find($id)]); }
    public function history(Request $r): never { Response::success((new Alert())->history((int)$r->user['id'],$r->user['municipality_id']?(int)$r->user['municipality_id']:null)); }
    public function unreadCount(Request $r): never { Response::success(['count'=>(new Alert())->unreadCount((int)$r->user['id'],$r->user['municipality_id']?(int)$r->user['municipality_id']:null)]); }
    public function markRead(Request $r): never { $id=(int)$r->params['id'];$item=$this->findOrFail($id);if($item['status']!=='sent'||($item['municipality_id']!==null&&(int)$item['municipality_id']!==(int)$r->user['municipality_id']))Response::error('Alert is not available to this user',403);(new Alert())->markRead($id,(int)$r->user['id']);Response::success(['message'=>'Alert marked as read']); }
    private function validated(Request $r): array
    {
        $d=$r->body();Validator::require($d,['title','alert_type','alert_level','message']);$errors=[];$title=trim((string)$d['title']);$message=trim((string)$d['message']);$mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:(isset($d['municipality_id'])&&$d['municipality_id']!==''?(int)$d['municipality_id']:null);if(strlen($title)<3||strlen($title)>180)$errors['title']='Must contain 3 to 180 characters';if(!in_array($d['alert_type'],self::TYPES,true))$errors['alert_type']='Invalid alert type';if(!in_array($d['alert_level'],self::LEVELS,true))$errors['alert_level']='Invalid alert level';if(strlen($message)<5||strlen($message)>10000)$errors['message']='Must contain 5 to 10000 characters';if($mid){$s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';}if($errors)Response::error('Validation failed',422,$errors);return ['title'=>$title,'alert_type'=>$d['alert_type'],'alert_level'=>$d['alert_level'],'message'=>$message,'municipality_id'=>$mid];
    }
    private function findOrFail(int $id): array { $item=(new Alert())->find($id);if(!$item)Response::error('Alert not found',404);return $item; }
    private function assertScope(Request $r,array $item): void { if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403); }
}
