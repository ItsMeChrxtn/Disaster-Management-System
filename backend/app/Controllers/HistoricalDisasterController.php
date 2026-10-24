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
        $d=$r->body();Validator::require($d,['title','disaster_type','date_occurred']);$title=trim((string)$d['title']);$type=trim((string)$d['disaster_type']);$event=trim((string)($d['event_name']??''));$description=trim((string)($d['description']??''));$source=trim((string)($d['source']??''));$errors=[];
        if(strlen($title)<2||strlen($title)>180)$errors['title']='Must contain 2 to 180 characters';if(strlen($type)<2||strlen($type)>80)$errors['disaster_type']='Must contain 2 to 80 characters';if(strlen($event)>160)$errors['event_name']='Must not exceed 160 characters';if(strlen($description)>5000)$errors['description']='Must not exceed 5000 characters';if(strlen($source)>255)$errors['source']='Must not exceed 255 characters';
        // An empty municipality means a province-wide record (e.g. an earthquake felt across Cavite).
        $mid=null;if(isset($d['municipality_id'])&&$d['municipality_id']!==''&&$d['municipality_id']!==null){$mid=filter_var($d['municipality_id'],FILTER_VALIDATE_INT,['options'=>['min_range'=>1]]);if($mid===false)$errors['municipality_id']='Must be a positive integer';}
        if(!$this->validDate((string)$d['date_occurred']))$errors['date_occurred']='Must use YYYY-MM-DD';elseif($d['date_occurred']>date('Y-m-d'))$errors['date_occurred']='Must not be in the future';
        $counts=[];foreach(['casualties','injured','evacuated_families'] as $field){$value=$d[$field]??0;$value=$value===''?0:$value;$counts[$field]=filter_var($value,FILTER_VALIDATE_INT,['options'=>['min_range'=>0]]);if($counts[$field]===false)$errors[$field]='Must be a non-negative integer';}
        $damages=filter_var(($d['damages']??0)===''?0:($d['damages']??0),FILTER_VALIDATE_FLOAT);if($damages===false||$damages<0||$damages>9999999999999.99)$errors['damages']='Must be a non-negative amount within the supported range';
        // Barangays arrive as a list or as text separated by new lines/semicolons; the count defaults to the list length.
        $list=is_array($d['affected_barangays']??null)?$d['affected_barangays']:preg_split('/[\n;]+/',(string)($d['affected_barangays']??''));
        $barangays=array_values(array_unique(array_filter(array_map(fn($b)=>mb_substr(trim((string)$b),0,120),$list),'strlen')));
        $barangayText=implode("\n",$barangays);if(strlen($barangayText)>20000)$errors['affected_barangays']='List is too long';
        $barangayCount=($d['affected_barangay_count']??'')===''?count($barangays):filter_var($d['affected_barangay_count'],FILTER_VALIDATE_INT,['options'=>['min_range'=>0,'max_range'=>2000]]);if($barangayCount===false)$errors['affected_barangay_count']='Must be a non-negative integer';
        if(!$errors&&$mid){$s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';}
        if($errors)Response::error('Validation failed',422,$errors);
        return ['title'=>$title,'disaster_type'=>$type,'event_name'=>$event?:null,'description'=>$description?:null,'municipality_id'=>$mid?(int)$mid:null,'date_occurred'=>$d['date_occurred'],'casualties'=>(int)$counts['casualties'],'injured'=>(int)$counts['injured'],'evacuated_families'=>(int)$counts['evacuated_families'],'affected_barangays'=>$barangayText?:null,'affected_barangay_count'=>(int)$barangayCount,'damages'=>(float)$damages,'source'=>$source?:null];
    }
    private function validDate(string $value): bool { $date=\DateTimeImmutable::createFromFormat('!Y-m-d',$value);return $date!==false&&$date->format('Y-m-d')===$value; }
}
