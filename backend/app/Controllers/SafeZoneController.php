<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\SafeZone;

final class SafeZoneController
{
    public function index(Request $r): never
    {
        $mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:($r->query('municipality_id')!==null?(int)$r->query('municipality_id'):null);Response::success((new SafeZone())->all($mid));
    }
    public function show(Request $r): never
    {
        $item=(new SafeZone())->find((int)$r->params['id'],true);if(!$item)Response::error('Safe zone not found',404);if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403);Response::success($item);
    }
    public function nearest(Request $r): never
    {
        $lat=filter_var($r->query('latitude'),FILTER_VALIDATE_FLOAT);$lng=filter_var($r->query('longitude'),FILTER_VALIDATE_FLOAT);$limit=max(1,min(20,(int)$r->query('limit',5)));if($lat===false||$lng===false||abs((float)$lat)>90||abs((float)$lng)>180)Response::error('Valid latitude and longitude are required',422);Response::success((new SafeZone())->nearest((float)$lat,(float)$lng,$limit));
    }
    public function store(Request $r): never { $data=$this->validated($r);$model=new SafeZone();$id=$model->create($data);Response::success($model->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$model=new SafeZone();$item=$model->find($id);if(!$item)Response::error('Safe zone not found',404);$this->assertScope($r,$item);$model->update($id,$this->validated($r));Response::success($model->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$model=new SafeZone();$item=$model->find($id);if(!$item)Response::error('Safe zone not found',404);$this->assertScope($r,$item);$model->deactivate($id);Response::success(['message'=>'Safe zone deleted']); }

    private function validated(Request $r): array
    {
        $d=$r->body();$required=['safezone_name','address','latitude','longitude','capacity'];if($r->user['role']==='admin')$required[]='municipality_id';Validator::require($d,$required);$errors=[];$name=trim((string)$d['safezone_name']);$address=trim((string)$d['address']);$description=trim((string)($d['description']??''));$lat=filter_var($d['latitude'],FILTER_VALIDATE_FLOAT);$lng=filter_var($d['longitude'],FILTER_VALIDATE_FLOAT);$capacity=filter_var($d['capacity'],FILTER_VALIDATE_INT,['options'=>['min_range'=>0]]);$mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:(int)$d['municipality_id'];
        if(strlen($name)<2||strlen($name)>180)$errors['safezone_name']='Must contain 2 to 180 characters';if(strlen($address)>255)$errors['address']='Must not exceed 255 characters';if(strlen($description)>5000)$errors['description']='Must not exceed 5000 characters';if($lat===false||abs((float)$lat)>90)$errors['latitude']='Must be between -90 and 90';if($lng===false||abs((float)$lng)>180)$errors['longitude']='Must be between -180 and 180';if($capacity===false)$errors['capacity']='Must be a non-negative whole number';
        $s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';if($errors)Response::error('Validation failed',422,$errors);
        return ['safezone_name'=>$name,'municipality_id'=>$mid,'address'=>$address,'latitude'=>(float)$lat,'longitude'=>(float)$lng,'capacity'=>(int)$capacity,'description'=>$description?:null];
    }
    private function assertScope(Request $r,array $item): void { if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403); }
}
