<?php
namespace App\Controllers;

use App\Core\{Database,Request,Response};
use App\Models\{EvacuationCenter,EvacuationRoute,Hazard,Municipality,SafeZone};

final class GisController
{
    public function layers(Request $r): never
    {
        $mid=$r->query('municipality_id');
        if($mid!==null&&$mid!==''&&filter_var($mid,FILTER_VALIDATE_INT,['options'=>['min_range'=>1]])===false)Response::error('Invalid municipality filter',422);
        $mid=$mid===''||$mid===null?null:(int)$mid;$hazards=[];
        foreach(['flood_zone','storm_surge_area','earthquake_area'] as $type)$hazards[$type]=$this->only((new Hazard())->all(['hazard_type'=>$type,'risk_level'=>null,'municipality_id'=>$mid,'search'=>null]),['id','hazard_name','hazard_type','municipality_id','municipality_name','risk_level','description','geojson_data']);
        Response::success(['municipalities'=>$this->only((new Municipality())->all(true),['id','municipality_name','center_lat','center_lng']),'flood_layer'=>$hazards['flood_zone'],'storm_surge_layer'=>$hazards['storm_surge_area'],'earthquake_layer'=>$hazards['earthquake_area'],'safe_zone_layer'=>$this->only((new SafeZone())->all($mid),['id','safezone_name','municipality_id','municipality_name','address','latitude','longitude','capacity','contact_person','contact_number','description']),'evacuation_center_layer'=>$this->only((new EvacuationCenter())->all($mid),['id','center_name','municipality_id','municipality_name','address','contact_person','contact_number','capacity','status','latitude','longitude']),'route_layer'=>$this->only((new EvacuationRoute())->all($mid),['id','route_name','municipality_id','municipality_name','start_location','end_location','geojson_data'])]);
    }
    public function coveredLocations(Request $r): never
    {
        $geometry=$this->geometry($r->body()['geojson_data']??null);
        if(!$geometry)Response::error('A Polygon or MultiPolygon hazard area is required',422,['geojson_data'=>'Draw a closed hazard area first']);
        $db=Database::connection();$mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:null;
        $municipalityScope=$mid?' AND id='.$mid:'';
        $municipalities=$db->query('SELECT id,municipality_name,center_lat latitude,center_lng longitude FROM municipalities WHERE status="active" AND center_lat IS NOT NULL AND center_lng IS NOT NULL'.$municipalityScope)->fetchAll();
        $safeZones=$db->query('SELECT s.id,s.safezone_name name,s.municipality_id,m.municipality_name,s.latitude,s.longitude FROM safe_zones s JOIN municipalities m ON m.id=s.municipality_id WHERE s.status="active"'.($mid?' AND s.municipality_id='.$mid:''))->fetchAll();
        $centers=$db->query('SELECT e.id,e.center_name name,e.municipality_id,m.municipality_name,e.latitude,e.longitude,e.status FROM evacuation_centers e JOIN municipalities m ON m.id=e.municipality_id WHERE e.status<>"deleted"'.($mid?' AND e.municipality_id='.$mid:''))->fetchAll();
        $inside=fn(array $row):bool=>$this->contains($geometry,(float)$row['longitude'],(float)$row['latitude']);
        $coveredMunicipalities=array_values(array_filter($municipalities,$inside));
        $coveredSafeZones=array_values(array_filter($safeZones,$inside));
        $coveredCenters=array_values(array_filter($centers,$inside));
        $municipalityIds=[];foreach(array_merge($coveredMunicipalities,$coveredSafeZones,$coveredCenters) as $row){$id=(int)($row['municipality_id']??$row['id']);$municipalityIds[$id]=true;}
        if($municipalityIds){$marks=implode(',',array_fill(0,count($municipalityIds),'?'));$s=$db->prepare("SELECT id,municipality_name,center_lat latitude,center_lng longitude FROM municipalities WHERE id IN ($marks) ORDER BY municipality_name");$s->execute(array_keys($municipalityIds));$coveredMunicipalities=$s->fetchAll();}
        Response::success(['municipalities'=>$coveredMunicipalities,'safe_zones'=>$coveredSafeZones,'evacuation_centers'=>$coveredCenters,'counts'=>['municipalities'=>count($coveredMunicipalities),'safe_zones'=>count($coveredSafeZones),'evacuation_centers'=>count($coveredCenters)]]);
    }
    private function geometry(mixed $value): ?array
    {
        if(!is_array($value))return null;if(($value['type']??'')==='Feature')$value=$value['geometry']??null;
        return is_array($value)&&in_array($value['type']??'',['Polygon','MultiPolygon'],true)&&isset($value['coordinates'])&&is_array($value['coordinates'])?$value:null;
    }
    private function contains(array $geometry,float $lng,float $lat): bool
    {
        $polygons=$geometry['type']==='Polygon'?[$geometry['coordinates']]:$geometry['coordinates'];
        foreach($polygons as $polygon){if(!$polygon||!$this->inRing($polygon[0]??[],$lng,$lat))continue;$inHole=false;foreach(array_slice($polygon,1) as $hole)if($this->inRing($hole,$lng,$lat)){$inHole=true;break;}if(!$inHole)return true;}return false;
    }
    private function inRing(array $ring,float $lng,float $lat): bool
    {
        $inside=false;$count=count($ring);if($count<4)return false;
        for($i=0,$j=$count-1;$i<$count;$j=$i++){$xi=(float)($ring[$i][0]??0);$yi=(float)($ring[$i][1]??0);$xj=(float)($ring[$j][0]??0);$yj=(float)($ring[$j][1]??0);$cross=(($yi>$lat)!==($yj>$lat))&&($lng<($xj-$xi)*($lat-$yi)/(($yj-$yi)?:1.0)+$xi);if($cross)$inside=!$inside;}return $inside;
    }
    private function only(array $rows,array $fields): array { return array_map(fn(array $row)=>array_intersect_key($row,array_flip($fields)),$rows); }
}
