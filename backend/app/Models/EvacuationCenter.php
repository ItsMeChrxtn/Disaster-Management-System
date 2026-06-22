<?php
namespace App\Models;

final class EvacuationCenter extends BaseModel
{
    private const SELECT='SELECT e.id,e.center_name,e.municipality_id,e.address,e.contact_number,e.capacity,e.status,e.latitude,e.longitude,e.created_at,e.updated_at,m.municipality_name FROM evacuation_centers e JOIN municipalities m ON m.id=e.municipality_id';
    public function all(?int $municipalityId=null): array
    {
        $sql=self::SELECT.' WHERE e.status<>"deleted"';$values=[];if($municipalityId){$sql.=' AND e.municipality_id=?';$values[]=$municipalityId;}$sql.=' ORDER BY e.center_name';$s=$this->db->prepare($sql);$s->execute($values);return $this->cast($s->fetchAll());
    }
    public function find(int $id): ?array { $s=$this->db->prepare(self::SELECT.' WHERE e.id=? AND e.status<>"deleted"');$s->execute([$id]);$rows=$this->cast($s->fetchAll());return $rows[0]??null; }
    public function create(array $d): int
    {
        $s=$this->db->prepare('INSERT INTO evacuation_centers (center_name,municipality_id,address,contact_number,capacity,status,latitude,longitude) VALUES (?,?,?,?,?,?,?,?)');$s->execute([$d['center_name'],$d['municipality_id'],$d['address'],$d['contact_number'],$d['capacity'],$d['status'],$d['latitude'],$d['longitude']]);return (int)$this->db->lastInsertId();
    }
    public function update(int $id,array $d): void { $this->db->prepare('UPDATE evacuation_centers SET center_name=?,municipality_id=?,address=?,contact_number=?,capacity=?,status=?,latitude=?,longitude=? WHERE id=?')->execute([$d['center_name'],$d['municipality_id'],$d['address'],$d['contact_number'],$d['capacity'],$d['status'],$d['latitude'],$d['longitude'],$id]); }
    public function delete(int $id): void { $this->db->prepare('UPDATE evacuation_centers SET status="deleted" WHERE id=?')->execute([$id]); }
    public function nearest(float $lat,float $lng,int $limit): array
    {
        $distance='6371*ACOS(LEAST(1,COS(RADIANS(?))*COS(RADIANS(e.latitude))*COS(RADIANS(e.longitude)-RADIANS(?))+SIN(RADIANS(?))*SIN(RADIANS(e.latitude))))';$sql='SELECT e.id,e.center_name,e.municipality_id,e.address,e.contact_number,e.capacity,e.status,e.latitude,e.longitude,m.municipality_name,'.$distance.' distance_km FROM evacuation_centers e JOIN municipalities m ON m.id=e.municipality_id WHERE e.status="available" ORDER BY distance_km LIMIT '.(int)$limit;$s=$this->db->prepare($sql);$s->execute([$lat,$lng,$lat]);$rows=$this->cast($s->fetchAll());foreach($rows as &$row)$row['distance_km']=round((float)$row['distance_km'],2);return $rows;
    }
    private function cast(array $rows): array { foreach($rows as &$row){$row['latitude']=(float)$row['latitude'];$row['longitude']=(float)$row['longitude'];$row['capacity']=(int)$row['capacity'];}return $rows; }
}
