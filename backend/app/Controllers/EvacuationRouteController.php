<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\{EvacuationCenter, EvacuationRoute, SafeZone};

final class EvacuationRouteController
{
    public function index(Request $r): never { $mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:($r->query('municipality_id')!==null?(int)$r->query('municipality_id'):null);Response::success((new EvacuationRoute())->all($mid)); }
    public function show(Request $r): never { $item=(new EvacuationRoute())->find((int)$r->params['id']);if(!$item)Response::error('Evacuation route not found',404);$this->assertScope($r,$item);Response::success($item); }
    public function store(Request $r): never { $data=$this->validated($r);$model=new EvacuationRoute();$id=$model->create($data);Response::success($model->find($id),201); }
    public function update(Request $r): never { $id=(int)$r->params['id'];$model=new EvacuationRoute();$item=$model->find($id);if(!$item)Response::error('Evacuation route not found',404);$this->assertScope($r,$item);$model->update($id,$this->validated($r));Response::success($model->find($id)); }
    public function destroy(Request $r): never { $id=(int)$r->params['id'];$model=new EvacuationRoute();$item=$model->find($id);if(!$item)Response::error('Evacuation route not found',404);$this->assertScope($r,$item);$model->delete($id);Response::success(['message'=>'Evacuation route deleted']); }
    public function nearestDestination(Request $r): never
    {
        [$lat,$lng]=$this->queryCoordinates($r);$type=(string)$r->query('type');if(!in_array($type,['safe_zone','evacuation_center'],true))Response::error('Type must be safe_zone or evacuation_center',422);$items=$type==='safe_zone'?(new SafeZone())->nearest($lat,$lng,1):(new EvacuationCenter())->nearest($lat,$lng,1);if(!$items)Response::error('No available destination found',404);Response::success(['type'=>$type,'destination'=>$items[0]]);
    }
    public function roadRoute(Request $r): never
    {
        $startLat=$this->coordinate($r->query('start_lat'),'start_lat',90);$startLng=$this->coordinate($r->query('start_lng'),'start_lng',180);$endLat=$this->coordinate($r->query('end_lat'),'end_lat',90);$endLng=$this->coordinate($r->query('end_lng'),'end_lng',180);
        $fallback=['type'=>'LineString','coordinates'=>[[$startLng,$startLat],[$endLng,$endLat]]];$url=sprintf('https://router.project-osrm.org/route/v1/driving/%.7F,%.7F;%.7F,%.7F?overview=full&geometries=geojson&steps=false',$startLng,$startLat,$endLng,$endLat);$context=stream_context_create(['http'=>['timeout'=>8,'header'=>"User-Agent: DisasterMap/1.0\r\n"]]);$raw=@file_get_contents($url,false,$context);$payload=$raw?json_decode($raw,true):null;$route=$payload['routes'][0]??null;
        Response::success(['geojson_data'=>$route['geometry']??$fallback,'distance_m'=>(float)($route['distance']??$this->haversine($startLat,$startLng,$endLat,$endLng)*1000),'duration_s'=>$route? (float)$route['duration']:null,'source'=>$route?'osrm':'straight_line_fallback']);
    }
    private function validated(Request $r): array
    {
        $d=$r->body();Validator::require($d,['route_name','start_location','end_location','geojson_data']);$errors=[];$name=trim((string)$d['route_name']);if(strlen($name)<2||strlen($name)>180)$errors['route_name']='Must contain 2 to 180 characters';foreach(['start_location','end_location'] as $field)if(!$this->validLocation($d[$field]))$errors[$field]='Must contain valid name, latitude, and longitude';$geo=$d['geojson_data'];if(!$this->validLine($geo))$errors['geojson_data']='Must be a GeoJSON LineString';$encoded=is_array($geo)?json_encode($geo,JSON_UNESCAPED_SLASHES):false;if($encoded===false||strlen($encoded)>2097152)$errors['geojson_data']='Route GeoJSON must not exceed 2 MB';if($errors)Response::error('Validation failed',422,$errors);
        $mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:(empty($d['municipality_id'])?null:(int)$d['municipality_id']);if(!$mid&&is_array($d['end_location'])){$s=Database::connection()->prepare('SELECT municipality_id FROM safe_zones WHERE latitude=? AND longitude=? UNION SELECT municipality_id FROM evacuation_centers WHERE latitude=? AND longitude=? LIMIT 1');$s->execute([$d['end_location']['latitude'],$d['end_location']['longitude'],$d['end_location']['latitude'],$d['end_location']['longitude']]);$mid=($found=$s->fetchColumn())?(int)$found:null;}if($mid){$s=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())Response::error('Validation failed',422,['municipality_id'=>'Municipality is invalid or inactive']);}
        $distance=isset($d['distance_km'])&&$d['distance_km']!==''?filter_var($d['distance_km'],FILTER_VALIDATE_FLOAT):null;$minutes=isset($d['estimated_travel_minutes'])&&$d['estimated_travel_minutes']!==''?filter_var($d['estimated_travel_minutes'],FILTER_VALIDATE_INT,['options'=>['min_range'=>0]]):null;if($distance!==null&&($distance===false||$distance<0))Response::error('Validation failed',422,['distance_km'=>'Must be a non-negative number']);if($minutes===false)Response::error('Validation failed',422,['estimated_travel_minutes'=>'Must be a non-negative whole number']);
        return ['route_name'=>$name,'municipality_id'=>$mid,'start_location'=>json_encode($d['start_location'],JSON_UNESCAPED_SLASHES),'end_location'=>json_encode($d['end_location'],JSON_UNESCAPED_SLASHES),'geojson_data'=>$encoded,'distance_km'=>$distance===null?null:round((float)$distance,2),'estimated_travel_minutes'=>$minutes===null?null:(int)$minutes];
    }
    private function validLocation(mixed $v): bool { return is_array($v)&&isset($v['name'],$v['latitude'],$v['longitude'])&&is_numeric($v['latitude'])&&is_numeric($v['longitude'])&&abs((float)$v['latitude'])<=90&&abs((float)$v['longitude'])<=180; }
    private function validLine(mixed $v): bool { if(!is_array($v))return false;if(($v['type']??null)==='Feature')$v=$v['geometry']??[];if(($v['type']??null)!=='LineString'||!isset($v['coordinates'])||!is_array($v['coordinates'])||count($v['coordinates'])<2)return false;foreach($v['coordinates'] as $point)if(!is_array($point)||count($point)<2||!is_numeric($point[0])||!is_numeric($point[1]))return false;return true; }
    private function queryCoordinates(Request $r): array { return [$this->coordinate($r->query('latitude'),'latitude',90),$this->coordinate($r->query('longitude'),'longitude',180)]; }
    private function coordinate(mixed $value,string $field,int $max): float { $number=filter_var($value,FILTER_VALIDATE_FLOAT);if($number===false||abs((float)$number)>$max)Response::error("Valid $field is required",422);return (float)$number; }
    private function haversine(float $lat1,float $lng1,float $lat2,float $lng2): float { $earth=6371;$dLat=deg2rad($lat2-$lat1);$dLng=deg2rad($lng2-$lng1);$a=sin($dLat/2)**2+cos(deg2rad($lat1))*cos(deg2rad($lat2))*sin($dLng/2)**2;return $earth*2*atan2(sqrt($a),sqrt(1-$a)); }
    private function assertScope(Request $r,array $item): void { if($r->user['role']==='subadmin'&&(int)$item['municipality_id']!==(int)$r->user['municipality_id'])Response::error('Forbidden',403); }
}
