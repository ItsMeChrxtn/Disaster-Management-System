<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response};
use App\Models\Hazard;
use PDO;

final class DashboardController
{
    public function index(Request $r): never
    {
        $db=Database::connection();$role=$r->user['role'];$mid=$r->user['municipality_id']?(int)$r->user['municipality_id']:null;
        $lat=filter_var($r->query('latitude'),FILTER_VALIDATE_FLOAT);$lng=filter_var($r->query('longitude'),FILTER_VALIDATE_FLOAT);$hasCoordinates=$lat!==false&&$lng!==false&&abs((float)$lat)<=90&&abs((float)$lng)<=180;
        $cards=$role==='resident'?$this->residentCards($db,$mid,$hasCoordinates?(float)$lat:null,$hasCoordinates?(float)$lng:null):$this->managerCards($db,$role,$mid,(int)$r->user['id']);
        $charts=$this->charts($db,$role,$mid);
        $center=$this->municipalityCenter($db,$mid);
        Response::success(['role'=>$role,'cards'=>$cards,'charts'=>$charts,'municipality_center'=>$center,'nearby_radius_km'=>20,'generated_at'=>gmdate(DATE_ATOM)]);
    }

    private function managerCards(PDO $db,string $role,?int $mid,int $userId): array
    {
        $scope=$role==='subadmin'?' AND municipality_id=:mid':'';$params=$role==='subadmin'?['mid'=>$mid]:[];
        $cards=[
            'total_residents'=>$this->count($db,'SELECT COUNT(*) FROM users WHERE role="resident" AND status="active"'.$scope,$params),
            'total_hazards'=>$this->count($db,'SELECT COUNT(*) FROM hazards WHERE status="active"'.$scope,$params),
            'total_safe_zones'=>$this->count($db,'SELECT COUNT(*) FROM safe_zones WHERE status="active"'.$scope,$params),
            'total_evacuation_centers'=>$this->count($db,'SELECT COUNT(*) FROM evacuation_centers WHERE status="available"'.$scope,$params),
            'total_alerts'=>$this->count($db,'SELECT COUNT(*) FROM alerts WHERE status="sent"'.$scope,$params),
            'total_reports'=>$this->count($db,'SELECT COUNT(*) FROM reports'.($role==='subadmin'?' WHERE generated_by=?':''),$role==='subadmin'?[$userId]:[]),
        ];
        if($role==='admin')$cards=array_merge(['total_residents'=>$cards['total_residents'],'total_municipalities'=>$this->count($db,'SELECT COUNT(*) FROM municipalities WHERE status="active"')],array_slice($cards,1,null,true));
        return $cards;
    }

    private function residentCards(PDO $db,?int $mid,?float $lat,?float $lng): array
    {
        $params=['mid'=>$mid??0];$alertSql='SELECT COUNT(*) FROM alerts WHERE status="sent" AND (municipality_id IS NULL OR municipality_id=:mid)';
        if($lat!==null&&$lng!==null){$distance='6371*ACOS(LEAST(1,COS(RADIANS(?))*COS(RADIANS(latitude))*COS(RADIANS(longitude)-RADIANS(?))+SIN(RADIANS(?))*SIN(RADIANS(latitude))))';$safe=$this->count($db,'SELECT COUNT(*) FROM safe_zones WHERE status="active" AND '.$distance.'<=20',[$lat,$lng,$lat]);$centers=$this->count($db,'SELECT COUNT(*) FROM evacuation_centers WHERE status="available" AND '.$distance.'<=20',[$lat,$lng,$lat]);}
        else{$safe=$this->count($db,'SELECT COUNT(*) FROM safe_zones WHERE status="active" AND municipality_id=:mid',$params);$centers=$this->count($db,'SELECT COUNT(*) FROM evacuation_centers WHERE status="available" AND municipality_id=:mid',$params);}
        return ['active_alerts'=>$this->count($db,$alertSql,$params),'nearby_safe_zones'=>$safe,'nearby_evacuation_centers'=>$centers,'weather_status'=>null];
    }

    private function charts(PDO $db,string $role,?int $mid): array
    {
        $scope=$role==='admin'?'':' AND municipality_id=:mid';$params=$role==='admin'?[]:['mid'=>$mid??0];
        new Hazard(); // ensures the barangays column exists before it is queried below
        $found=[];foreach($this->rows($db,'SELECT risk_level label,COUNT(*) value FROM hazards WHERE status="active"'.$scope.' GROUP BY risk_level',$params) as $row)$found[$row['label']]=$row['value'];
        $severity=array_map(fn($level)=>['label'=>$level,'value'=>$found[$level]??0],['critical','high','moderate','low']);
        $byType=$this->rows($db,'SELECT hazard_type label,COUNT(*) value FROM hazards WHERE status="active"'.$scope.' GROUP BY hazard_type ORDER BY value DESC',$params);
        $alertScope=$role==='admin'?'':' AND (a.municipality_id IS NULL OR a.municipality_id=:mid)';$sentAt='COALESCE(a.sent_at,a.created_at)';
        $months=[];for($n=5;$n>=0;$n--){$key=gmdate('Y-m',strtotime(gmdate('Y-m-01')." -$n month"));$months[$key]=['label'=>gmdate('M Y',strtotime($key.'-01')),'month'=>$key,'value'=>0,'levels'=>['info'=>0,'advisory'=>0,'warning'=>0,'critical'=>0]];}
        $s=$db->prepare('SELECT a.id,a.title,a.alert_type,a.alert_level,'.$sentAt.' sent_at,m.municipality_name FROM alerts a LEFT JOIN municipalities m ON m.id=a.municipality_id WHERE a.status="sent" AND '.$sentAt.'>=:since'.$alertScope.' ORDER BY '.$sentAt.' DESC');
        $s->execute(['since'=>array_key_first($months).'-01']+$params);$history=[];
        foreach($s->fetchAll() as $row){$key=substr((string)$row['sent_at'],0,7);if(isset($months[$key])){$months[$key]['value']++;$months[$key]['levels'][$row['alert_level']]=($months[$key]['levels'][$row['alert_level']]??0)+1;}$history[]=['id'=>(int)$row['id'],'title'=>$row['title'],'alert_type'=>$row['alert_type'],'alert_level'=>$row['alert_level'],'sent_at'=>$row['sent_at'],'municipality_name'=>$row['municipality_name']];}
        $facilities=[['label'=>'Safe zones','value'=>$this->count($db,'SELECT COUNT(*) FROM safe_zones WHERE status="active"'.$scope,$params)],['label'=>'Evacuation centers','value'=>$this->count($db,'SELECT COUNT(*) FROM evacuation_centers WHERE status="available"'.$scope,$params)]];
        return ['hazards_by_severity'=>$severity,'hazards_by_type'=>$byType,'hazards_by_area'=>$this->hazardsByArea($db,$scope,$params),'alerts_last_six_months'=>array_values($months),'alert_history'=>$history,'facilities'=>$facilities];
    }

    // Per-municipality hazard breakdown with the barangays each hazard covers.
    private function hazardsByArea(PDO $db,string $scope,array $params): array
    {
        $rank=['low'=>1,'moderate'=>2,'high'=>3,'critical'=>4];$areas=[];
        $s=$db->prepare('SELECT h.hazard_type,h.risk_level,h.barangays,h.municipality_id,COALESCE(m.municipality_name,"Province-wide") municipality_name FROM hazards h LEFT JOIN municipalities m ON m.id=h.municipality_id WHERE h.status="active"'.str_replace('municipality_id','h.municipality_id',$scope));$s->execute($params);
        foreach($s->fetchAll() as $row){
            $name=$row['municipality_name'];$area=&$areas[$name];
            $area??=['municipality_name'=>$name,'municipality_id'=>$row['municipality_id']===null?null:(int)$row['municipality_id'],'total'=>0,'types'=>[],'highest_risk'=>'low','barangays'=>[]];
            $area['total']++;$area['types'][$row['hazard_type']]=($area['types'][$row['hazard_type']]??0)+1;
            if($rank[$row['risk_level']]>$rank[$area['highest_risk']])$area['highest_risk']=$row['risk_level'];
            foreach(array_filter(array_map('trim',explode(',',(string)$row['barangays']))) as $barangay)$area['barangays'][$barangay]=($area['barangays'][$barangay]??0)+1;
            unset($area);
        }
        $areas=array_values($areas);usort($areas,fn($a,$b)=>[$rank[$b['highest_risk']],$b['total']]<=>[$rank[$a['highest_risk']],$a['total']]);
        foreach($areas as &$area){arsort($area['barangays']);$area['barangays']=array_map(fn($name,$count)=>['name'=>$name,'hazards'=>$count],array_keys($area['barangays']),$area['barangays']);}
        return $areas;
    }

    private function municipalityCenter(PDO $db,?int $mid): ?array
    {
        if(!$mid)return null;$s=$db->prepare('SELECT center_lat latitude,center_lng longitude FROM municipalities WHERE id=?');$s->execute([$mid]);$row=$s->fetch();return $row&&$row['latitude']!==null?['latitude'=>(float)$row['latitude'],'longitude'=>(float)$row['longitude']]:null;
    }
    private function count(PDO $db,string $sql,array $params=[]): int { $s=$db->prepare($sql);$s->execute($params);return (int)$s->fetchColumn(); }
    private function rows(PDO $db,string $sql,array $params=[]): array { $s=$db->prepare($sql);$s->execute($params);return array_map(fn($row)=>['label'=>$row['label'],'value'=>(int)$row['value']],$s->fetchAll()); }
}
