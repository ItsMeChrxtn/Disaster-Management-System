<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\{Notification, SafeZone};

final class SafeZoneController
{
    public function index(Request $r): never
    {
        $mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:($r->query('municipality_id')!==null&&$r->query('municipality_id')!==''?(int)$r->query('municipality_id'):null);Response::success((new SafeZone())->all($mid));
    }
    public function show(Request $r): never
    {
        $item=(new SafeZone())->find((int)$r->params['id'],true);if(!$item)Response::error('Safe zone not found',404);if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403);Response::success($item);
    }
    public function nearest(Request $r): never
    {
        $lat=filter_var($r->query('latitude'),FILTER_VALIDATE_FLOAT);$lng=filter_var($r->query('longitude'),FILTER_VALIDATE_FLOAT);$limit=max(1,min(20,(int)$r->query('limit',5)));if($lat===false||$lng===false||abs((float)$lat)>90||abs((float)$lng)>180)Response::error('Valid latitude and longitude are required',422);Response::success((new SafeZone())->nearest((float)$lat,(float)$lng,$limit));
    }
    public function store(Request $r): never { $data=$this->validated($r);$model=new SafeZone();$id=$model->create($data);$this->notifyChange($r,$data,'added');Response::success($model->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$model=new SafeZone();$item=$model->find($id);if(!$item)Response::error('Safe zone not found',404);$this->assertScope($r,$item);$data=$this->validated($r);$model->update($id,$data);$this->notifyChange($r,$data,'updated');Response::success($model->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$model=new SafeZone();$item=$model->find($id);if(!$item)Response::error('Safe zone not found',404);$this->assertScope($r,$item);$model->deactivate($id);Response::success(['message'=>'Safe zone deleted']); }

    private function validated(Request $r): array
    {
        $d=$r->body();$required=['safezone_name','address','latitude','longitude','capacity'];if($r->user['role']==='admin')$required[]='municipality_id';Validator::require($d,$required);$errors=[];$name=trim((string)$d['safezone_name']);$address=trim((string)$d['address']);$contactPerson=trim((string)($d['contact_person']??''));$contactNumber=trim((string)($d['contact_number']??''));$description=trim((string)($d['description']??''));$lat=filter_var($d['latitude'],FILTER_VALIDATE_FLOAT);$lng=filter_var($d['longitude'],FILTER_VALIDATE_FLOAT);$capacity=filter_var($d['capacity'],FILTER_VALIDATE_INT,['options'=>['min_range'=>0]]);$mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:(int)$d['municipality_id'];
        if(strlen($name)<2||strlen($name)>180)$errors['safezone_name']='Must contain 2 to 180 characters';if(strlen($address)>255)$errors['address']='Must not exceed 255 characters';if(strlen($contactPerson)>120)$errors['contact_person']='Must not exceed 120 characters';if(strlen($contactNumber)>30)$errors['contact_number']='Must not exceed 30 characters';if(strlen($description)>5000)$errors['description']='Must not exceed 5000 characters';if($lat===false||abs((float)$lat)>90)$errors['latitude']='Must be between -90 and 90';if($lng===false||abs((float)$lng)>180)$errors['longitude']='Must be between -180 and 180';if($capacity===false)$errors['capacity']='Must be a non-negative whole number';$radius=null;if(isset($d['perimeter_radius_m'])&&$d['perimeter_radius_m']!==''){$radius=filter_var($d['perimeter_radius_m'],FILTER_VALIDATE_INT,['options'=>['min_range'=>10,'max_range'=>5000]]);if($radius===false)$errors['perimeter_radius_m']='Must be between 10 and 5000 meters';}
        $s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';if($errors)Response::error('Validation failed',422,$errors);
        return ['safezone_name'=>$name,'municipality_id'=>$mid,'address'=>$address,'latitude'=>(float)$lat,'longitude'=>(float)$lng,'capacity'=>(int)$capacity,'perimeter_radius_m'=>$radius?:null,'contact_person'=>$contactPerson?:null,'contact_number'=>$contactNumber?:null,'description'=>$description?:null];
    }
    private function assertScope(Request $r,array $item): void { if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403); }
    private function notifyChange(Request $r,array $data,string $verb): void
    {
        $n=new Notification();
        if($r->user['role']==='subadmin')$n->notifyRole('admin',null,'system_update','Safety facility '.$verb,$r->user['fullname'].' '.$verb.' a safety facility "'.$data['safezone_name'].'" in '.($r->user['municipality_name']??'their municipality').'.');
        elseif($r->user['role']==='admin')$n->notifyRole('subadmin',$data['municipality_id'],'system_update','Safety facility '.$verb.' for your municipality',$r->user['fullname'].' '.$verb.' a safety facility "'.$data['safezone_name'].'" for your municipality.');
    }
}
