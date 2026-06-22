<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\EvacuationCenter;

final class EvacuationCenterController
{
    public function index(Request $r): never { $mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:($r->query('municipality_id')!==null?(int)$r->query('municipality_id'):null);Response::success((new EvacuationCenter())->all($mid)); }
    public function show(Request $r): never { $item=(new EvacuationCenter())->find((int)$r->params['id']);if(!$item)Response::error('Evacuation center not found',404);$this->assertScope($r,$item);Response::success($item); }
    public function nearest(Request $r): never
    {
        $lat=filter_var($r->query('latitude'),FILTER_VALIDATE_FLOAT);$lng=filter_var($r->query('longitude'),FILTER_VALIDATE_FLOAT);$limit=max(1,min(20,(int)$r->query('limit',5)));if($lat===false||$lng===false||abs((float)$lat)>90||abs((float)$lng)>180)Response::error('Valid latitude and longitude are required',422);Response::success((new EvacuationCenter())->nearest((float)$lat,(float)$lng,$limit));
    }
    public function store(Request $r): never { $data=$this->validated($r);$model=new EvacuationCenter();$id=$model->create($data);Response::success($model->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$model=new EvacuationCenter();$item=$model->find($id);if(!$item)Response::error('Evacuation center not found',404);$this->assertScope($r,$item);$model->update($id,$this->validated($r));Response::success($model->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$model=new EvacuationCenter();$item=$model->find($id);if(!$item)Response::error('Evacuation center not found',404);$this->assertScope($r,$item);$model->delete($id);Response::success(['message'=>'Evacuation center deleted']); }
    private function validated(Request $r): array
    {
        $d=$r->body();$required=['center_name','address','capacity','status','latitude','longitude'];if($r->user['role']==='admin')$required[]='municipality_id';Validator::require($d,$required);$errors=[];$name=trim((string)$d['center_name']);$address=trim((string)$d['address']);$contact=trim((string)($d['contact_number']??''));$capacity=filter_var($d['capacity'],FILTER_VALIDATE_INT,['options'=>['min_range'=>0]]);$lat=filter_var($d['latitude'],FILTER_VALIDATE_FLOAT);$lng=filter_var($d['longitude'],FILTER_VALIDATE_FLOAT);$mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:(int)$d['municipality_id'];
        if(strlen($name)<2||strlen($name)>180)$errors['center_name']='Must contain 2 to 180 characters';if($address===''||strlen($address)>255)$errors['address']='Required and must not exceed 255 characters';if(strlen($contact)>30)$errors['contact_number']='Must not exceed 30 characters';if($capacity===false)$errors['capacity']='Must be a non-negative whole number';if(!in_array($d['status'],['available','full','closed','under_maintenance'],true))$errors['status']='Select a supported operating status';if($lat===false||abs((float)$lat)>90)$errors['latitude']='Must be between -90 and 90';if($lng===false||abs((float)$lng)>180)$errors['longitude']='Must be between -180 and 180';
        $s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';if($errors)Response::error('Validation failed',422,$errors);
        return ['center_name'=>$name,'municipality_id'=>$mid,'address'=>$address,'contact_number'=>$contact?:null,'capacity'=>(int)$capacity,'status'=>$d['status'],'latitude'=>(float)$lat,'longitude'=>(float)$lng];
    }
    private function assertScope(Request $r,array $item): void { if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403); }
}
