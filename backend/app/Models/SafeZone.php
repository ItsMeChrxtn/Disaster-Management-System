<?php
namespace App\Models;

final class SafeZone extends BaseModel
{
    private const SELECT='SELECT s.id,s.safezone_name,s.municipality_id,s.address,s.latitude,s.longitude,s.capacity,s.description,s.status,s.created_at,s.updated_at,m.municipality_name FROM safe_zones s JOIN municipalities m ON m.id=s.municipality_id';
    public function all(?int $municipalityId=null): array
    {
        $sql=self::SELECT.' WHERE s.status="active"';$values=[];if($municipalityId){$sql.=' AND s.municipality_id=?';$values[]=$municipalityId;}$sql.=' ORDER BY s.safezone_name';$s=$this->db->prepare($sql);$s->execute($values);return $this->cast($s->fetchAll());
    }
    public function find(int $id,bool $activeOnly=false): ?array
    {
        $s=$this->db->prepare(self::SELECT.' WHERE s.id=?'.($activeOnly?' AND s.status="active"':''));$s->execute([$id]);$rows=$this->cast($s->fetchAll());return $rows[0]??null;
    }
    public function create(array $d): int
    {
        $s=$this->db->prepare('INSERT INTO safe_zones (safezone_name,municipality_id,address,latitude,longitude,capacity,description,status) VALUES (?,?,?,?,?,?,?,"active")');$s->execute([$d['safezone_name'],$d['municipality_id'],$d['address'],$d['latitude'],$d['longitude'],$d['capacity'],$d['description']]);return (int)$this->db->lastInsertId();
    }
    public function update(int $id,array $d): void { $this->db->prepare('UPDATE safe_zones SET safezone_name=?,municipality_id=?,address=?,latitude=?,longitude=?,capacity=?,description=? WHERE id=?')->execute([$d['safezone_name'],$d['municipality_id'],$d['address'],$d['latitude'],$d['longitude'],$d['capacity'],$d['description'],$id]); }
    public function deactivate(int $id): void { $this->db->prepare('UPDATE safe_zones SET status="inactive" WHERE id=?')->execute([$id]); }
    public function nearest(float $lat,float $lng,int $limit): array
    {
        $distance='6371*ACOS(LEAST(1,COS(RADIANS(?))*COS(RADIANS(s.latitude))*COS(RADIANS(s.longitude)-RADIANS(?))+SIN(RADIANS(?))*SIN(RADIANS(s.latitude))))';
        $sql='SELECT s.id,s.safezone_name,s.municipality_id,s.address,s.latitude,s.longitude,s.capacity,s.description,m.municipality_name,'.$distance.' distance_km FROM safe_zones s JOIN municipalities m ON m.id=s.municipality_id WHERE s.status="active" ORDER BY distance_km LIMIT '.(int)$limit;$s=$this->db->prepare($sql);$s->execute([$lat,$lng,$lat]);$rows=$this->cast($s->fetchAll());foreach($rows as &$row)$row['distance_km']=round((float)$row['distance_km'],2);return $rows;
    }
    private function cast(array $rows): array { foreach($rows as &$row){$row['latitude']=(float)$row['latitude'];$row['longitude']=(float)$row['longitude'];$row['capacity']=$row['capacity']===null?null:(int)$row['capacity'];}return $rows; }
}

