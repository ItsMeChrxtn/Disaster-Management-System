<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response};
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
        if($role==='admin')$cards=['total_residents'=>$cards['total_residents'],'total_municipalities'=>$this->count($db,'SELECT COUNT(*) FROM municipalities WHERE status="active"'),...array_slice($cards,1,null,true)];
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
        $severity=$this->rows($db,'SELECT risk_level label,COUNT(*) value FROM hazards WHERE status="active"'.$scope.' GROUP BY risk_level ORDER BY FIELD(risk_level,"critical","high","moderate","low")',$params);
        $alerts=$this->rows($db,'SELECT DATE_FORMAT(months.month_start,"%b") label,COUNT(a.id) value FROM (SELECT DATE_FORMAT(DATE_SUB(UTC_DATE(),INTERVAL n MONTH),"%Y-%m-01") month_start FROM (SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) x) months LEFT JOIN alerts a ON DATE_FORMAT(a.created_at,"%Y-%m-01")=months.month_start'.($role==='admin'?'':' AND a.municipality_id=:mid').' GROUP BY months.month_start ORDER BY months.month_start',$params);
        $facilities=[['label'=>'Safe zones','value'=>$this->count($db,'SELECT COUNT(*) FROM safe_zones WHERE status="active"'.$scope,$params)],['label'=>'Evacuation centers','value'=>$this->count($db,'SELECT COUNT(*) FROM evacuation_centers WHERE status="available"'.$scope,$params)]];
        return ['hazards_by_severity'=>$severity,'alerts_last_six_months'=>$alerts,'facilities'=>$facilities];
    }

    private function municipalityCenter(PDO $db,?int $mid): ?array
    {
        if(!$mid)return null;$s=$db->prepare('SELECT center_lat latitude,center_lng longitude FROM municipalities WHERE id=?');$s->execute([$mid]);$row=$s->fetch();return $row&&$row['latitude']!==null?['latitude'=>(float)$row['latitude'],'longitude'=>(float)$row['longitude']]:null;
    }
    private function count(PDO $db,string $sql,array $params=[]): int { $s=$db->prepare($sql);$s->execute($params);return (int)$s->fetchColumn(); }
    private function rows(PDO $db,string $sql,array $params=[]): array { $s=$db->prepare($sql);$s->execute($params);return array_map(fn($row)=>['label'=>$row['label'],'value'=>(int)$row['value']],$s->fetchAll()); }
}
