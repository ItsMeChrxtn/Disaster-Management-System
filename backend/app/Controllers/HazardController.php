<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\Hazard;

final class HazardController
{
    private const TYPES=['flood_zone','storm_surge_area','landslide','earthquake_area','fire','high_risk_area'];
    private const RISKS=['low','moderate','high','critical'];
    private const GEOJSON_TYPES=['FeatureCollection','Feature','Point','MultiPoint','LineString','MultiLineString','Polygon','MultiPolygon','GeometryCollection'];

    public function index(Request $r): never
    {
        $filters=['hazard_type'=>$this->nullable($r->query('hazard_type')),'risk_level'=>$this->nullable($r->query('risk_level')),'municipality_id'=>$this->nullable($r->query('municipality_id')),'search'=>$this->nullable(trim((string)$r->query('search','')))];
        if($filters['hazard_type']!==null&&!$this->validHazardTypeFilter((string)$filters['hazard_type']))Response::error('Invalid hazard type filter',422);if($filters['risk_level']&&!in_array($filters['risk_level'],self::RISKS,true))Response::error('Invalid risk level filter',422);if($filters['municipality_id']!==null&&!ctype_digit((string)$filters['municipality_id']))Response::error('Invalid municipality filter',422);if($filters['search']!==null&&strlen($filters['search'])>100)Response::error('Search must not exceed 100 characters',422);
        Response::success((new Hazard())->all($filters));
    }
    public function show(Request $r): never { $item=(new Hazard())->find((int)$r->params['id'],true);if(!$item)Response::error('Hazard not found',404);Response::success($item); }
    public function store(Request $r): never { $data=$this->validated($r);$model=new Hazard();$id=$model->create($data,(int)$r->user['id']);Response::success($model->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$model=new Hazard();$item=$model->find($id);if(!$item)Response::error('Hazard not found',404);$this->assertScope($r,$item);$model->update($id,$this->validated($r));Response::success($model->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$model=new Hazard();$item=$model->find($id);if(!$item)Response::error('Hazard not found',404);$this->assertScope($r,$item);$model->archive($id);Response::success(['message'=>'Hazard deleted']); }

    private function validated(Request $r): array
    {
        $d=$r->body();$required=['hazard_name','hazard_type','risk_level','geojson_data'];if($r->user['role']==='admin')$required[]='municipality_id';Validator::require($d,$required);$errors=[];$name=trim((string)$d['hazard_name']);$type=$this->validatedHazardType($d,$errors);$description=trim((string)($d['description']??''));$mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:(int)$d['municipality_id'];
        if(strlen($name)<2||strlen($name)>180)$errors['hazard_name']='Must contain 2 to 180 characters';if(!in_array($d['risk_level'],self::RISKS,true))$errors['risk_level']='Invalid risk level';if(strlen($description)>5000)$errors['description']='Must not exceed 5000 characters';
        $geojson=$d['geojson_data'];if(!is_array($geojson)||!$this->validGeoJson($geojson))$errors['geojson_data']='Must be valid GeoJSON with coordinates';else{$encoded=json_encode($geojson,JSON_UNESCAPED_SLASHES);if($encoded===false||strlen($encoded)>2097152)$errors['geojson_data']='GeoJSON must not exceed 2 MB';}
        $s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';if($errors)Response::error('Validation failed',422,$errors);
        return ['hazard_name'=>$name,'hazard_type'=>$type,'municipality_id'=>$mid,'risk_level'=>$d['risk_level'],'description'=>$description?:null,'geojson_data'=>$encoded];
    }
    private function validatedHazardType(array $data,array &$errors): string
    {
        $type=trim((string)($data['hazard_type']??''));
        if($type==='other'){
            $custom=trim((string)($data['hazard_type_other']??''));
            if(strlen($custom)<2||strlen($custom)>80)$errors['hazard_type_other']='Enter a hazard type with 2 to 80 characters';
            if(preg_match('/[\x00-\x1F\x7F]/',$custom))$errors['hazard_type_other']='Hazard type contains invalid characters';
            return $custom;
        }
        if(!in_array($type,self::TYPES,true))$errors['hazard_type']='Invalid hazard type';
        return $type;
    }
    private function validHazardTypeFilter(string $type): bool
    {
        $type=trim($type);
        if($type==='other'||in_array($type,self::TYPES,true))return true;
        return strlen($type)>=2&&strlen($type)<=80&&!preg_match('/[\x00-\x1F\x7F]/',$type);
    }
    private function validGeoJson(array $value): bool
    {
        $type=$value['type']??null;if(!in_array($type,self::GEOJSON_TYPES,true))return false;
        if($type==='FeatureCollection')return isset($value['features'])&&is_array($value['features'])&&$value['features']!==[]&&array_reduce($value['features'],fn($ok,$v)=>$ok&&is_array($v)&&$this->validGeoJson($v),true);
        if($type==='Feature')return isset($value['geometry'])&&is_array($value['geometry'])&&$this->validGeoJson($value['geometry']);
        if($type==='GeometryCollection')return isset($value['geometries'])&&is_array($value['geometries'])&&$value['geometries']!==[]&&array_reduce($value['geometries'],fn($ok,$v)=>$ok&&is_array($v)&&$this->validGeoJson($v),true);
        return isset($value['coordinates'])&&is_array($value['coordinates'])&&$value['coordinates']!==[]&&$this->coordinatesNumeric($value['coordinates']);
    }
    private function coordinatesNumeric(array $coordinates): bool { foreach($coordinates as $value){if(is_array($value)){if(!$this->coordinatesNumeric($value))return false;}elseif(!is_int($value)&&!is_float($value))return false;}return true; }
    private function nullable(mixed $value): mixed { return $value===null||$value===''?null:$value; }
    private function assertScope(Request $r,array $item): void { if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403); }
}
