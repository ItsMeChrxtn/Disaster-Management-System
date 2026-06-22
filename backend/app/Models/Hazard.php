<?php
namespace App\Models;

final class Hazard extends BaseModel
{
    private const SELECT='SELECT h.id,h.hazard_name,h.hazard_type,h.municipality_id,h.risk_level,h.description,h.geojson_data,h.status,h.created_at,h.updated_at,m.municipality_name,u.fullname created_by_name FROM hazards h LEFT JOIN municipalities m ON m.id=h.municipality_id LEFT JOIN users u ON u.id=h.created_by';
    public function all(array $filters): array
    {
        $where=['h.status="active"'];$values=[];
        foreach(['hazard_type','risk_level','municipality_id'] as $field)if($filters[$field]!==null){$where[]='h.'.$field.'=?';$values[]=$filters[$field];}
        if($filters['search']!==null){$where[]='(h.hazard_name LIKE ? OR h.description LIKE ? OR m.municipality_name LIKE ?)';$term='%'.$filters['search'].'%';array_push($values,$term,$term,$term);}
        $s=$this->db->prepare(self::SELECT.' WHERE '.implode(' AND ',$where).' ORDER BY h.created_at DESC LIMIT 500');$s->execute($values);return $this->decode($s->fetchAll());
    }
    public function find(int $id,bool $activeOnly=false): ?array
    {
        $s=$this->db->prepare(self::SELECT.' WHERE h.id=?'.($activeOnly?' AND h.status="active"':''));$s->execute([$id]);$rows=$this->decode($s->fetchAll());return $rows[0]??null;
    }
    public function create(array $d,int $userId): int
    {
        $s=$this->db->prepare('INSERT INTO hazards (hazard_name,hazard_type,municipality_id,risk_level,description,geojson_data,created_by,status) VALUES (?,?,?,?,?,?,?,"active")');$s->execute([$d['hazard_name'],$d['hazard_type'],$d['municipality_id'],$d['risk_level'],$d['description'],$d['geojson_data'],$userId]);return (int)$this->db->lastInsertId();
    }
    public function update(int $id,array $d): void { $this->db->prepare('UPDATE hazards SET hazard_name=?,hazard_type=?,municipality_id=?,risk_level=?,description=?,geojson_data=? WHERE id=?')->execute([$d['hazard_name'],$d['hazard_type'],$d['municipality_id'],$d['risk_level'],$d['description'],$d['geojson_data'],$id]); }
    public function archive(int $id): void { $this->db->prepare('UPDATE hazards SET status="archived" WHERE id=?')->execute([$id]); }
    private function decode(array $rows): array { foreach($rows as &$row)$row['geojson_data']=json_decode($row['geojson_data'],true);return $rows; }
}

