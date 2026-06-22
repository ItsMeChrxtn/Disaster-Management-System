<?php
namespace App\Controllers;

use App\Core\{Database,Request,Response,Validator};
use App\Models\HistoricalDisaster;

final class HistoricalDisasterController
{
    public function index(Request $r): never
    {
        $filters=[];$errors=[];
        $search=trim((string)$r->query('search',''));if(strlen($search)>100)$errors['search']='Must not exceed 100 characters';elseif($search!=='')$filters['search']=$search;
        $type=trim((string)$r->query('disaster_type',''));if(strlen($type)>80)$errors['disaster_type']='Must not exceed 80 characters';elseif($type!=='')$filters['disaster_type']=$type;
        $mid=$r->query('municipality_id');if($mid!==null&&$mid!==''){if(filter_var($mid,FILTER_VALIDATE_INT,['options'=>['min_range'=>1]])===false)$errors['municipality_id']='Must be a positive integer';else $filters['municipality_id']=(int)$mid;}
        foreach(['date_from','date_to'] as $field){$value=trim((string)$r->query($field,''));if($value!==''&&!$this->validDate($value))$errors[$field]='Must use YYYY-MM-DD';elseif($value!=='')$filters[$field]=$value;}
        if(isset($filters['date_from'],$filters['date_to'])&&$filters['date_from']>$filters['date_to'])$errors['date_to']='Must be on or after date_from';
        if($errors)Response::error('Validation failed',422,$errors);Response::success((new HistoricalDisaster())->all($filters));
    }
    public function show(Request $r): never { $item=(new HistoricalDisaster())->find((int)$r->params['id']);if(!$item)Response::error('Historical disaster not found',404);Response::success($item); }
    public function store(Request $r): never { $d=$this->validated($r);$m=new HistoricalDisaster();$id=$m->create($d);Response::success($m->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$m=new HistoricalDisaster();if(!$m->find($id))Response::error('Historical disaster not found',404);$m->update($id,$this->validated($r));Response::success($m->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$m=new HistoricalDisaster();if(!$m->find($id))Response::error('Historical disaster not found',404);$m->delete($id);Response::success(['message'=>'Historical disaster deleted']); }
    private function validated(Request $r): array
    {
        $d=$r->body();Validator::require($d,['title','disaster_type','municipality_id','date_occurred','casualties','damages']);$title=trim((string)$d['title']);$type=trim((string)$d['disaster_type']);$description=trim((string)($d['description']??''));$errors=[];
        if(strlen($title)<2||strlen($title)>180)$errors['title']='Must contain 2 to 180 characters';if(strlen($type)<2||strlen($type)>80)$errors['disaster_type']='Must contain 2 to 80 characters';if(strlen($description)>5000)$errors['description']='Must not exceed 5000 characters';
        $mid=filter_var($d['municipality_id'],FILTER_VALIDATE_INT,['options'=>['min_range'=>1]]);if($mid===false)$errors['municipality_id']='Must be a positive integer';
        if(!$this->validDate((string)$d['date_occurred']))$errors['date_occurred']='Must use YYYY-MM-DD';elseif($d['date_occurred']>date('Y-m-d'))$errors['date_occurred']='Must not be in the future';
        $casualties=filter_var($d['casualties'],FILTER_VALIDATE_INT,['options'=>['min_range'=>0]]);if($casualties===false)$errors['casualties']='Must be a non-negative integer';
        $damages=filter_var($d['damages'],FILTER_VALIDATE_FLOAT);if($damages===false||$damages<0||$damages>9999999999999.99)$errors['damages']='Must be a non-negative amount within the supported range';
        if(!$errors){$s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';}
        if($errors)Response::error('Validation failed',422,$errors);
        return ['title'=>$title,'disaster_type'=>$type,'description'=>$description?:null,'municipality_id'=>(int)$mid,'date_occurred'=>$d['date_occurred'],'casualties'=>(int)$casualties,'damages'=>(float)$damages];
    }
    private function validDate(string $value): bool { $date=\DateTimeImmutable::createFromFormat('!Y-m-d',$value);return $date!==false&&$date->format('Y-m-d')===$value; }
}
