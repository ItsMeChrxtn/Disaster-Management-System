<?php
namespace App\Models;

final class HistoricalDisaster extends BaseModel
{
    public function all(array $filters=[]): array
    {
        $sql='SELECT d.id,d.title,d.disaster_type,d.description,d.municipality_id,COALESCE(m.municipality_name,"Province-wide") municipality_name,d.date_occurred,d.casualties,d.damages FROM historical_disasters d LEFT JOIN municipalities m ON m.id=d.municipality_id';
        $where=[];$values=[];
        if(!empty($filters['search'])){$where[]='(d.title LIKE ? OR d.description LIKE ? OR d.disaster_type LIKE ?)';$term='%'.$filters['search'].'%';array_push($values,$term,$term,$term);}
        if(!empty($filters['disaster_type'])){$where[]='d.disaster_type=?';$values[]=$filters['disaster_type'];}
        if(!empty($filters['municipality_id'])){$where[]='d.municipality_id=?';$values[]=$filters['municipality_id'];}
        if(!empty($filters['date_from'])){$where[]='d.date_occurred>=?';$values[]=$filters['date_from'];}
        if(!empty($filters['date_to'])){$where[]='d.date_occurred<=?';$values[]=$filters['date_to'];}
        if($where)$sql.=' WHERE '.implode(' AND ',$where);
        $sql.=' ORDER BY d.date_occurred DESC,d.id DESC LIMIT 500';
        $s=$this->db->prepare($sql);$s->execute($values);return array_map([$this,'cast'],$s->fetchAll());
    }
    public function find(int $id): ?array
    {
        $s=$this->db->prepare('SELECT d.id,d.title,d.disaster_type,d.description,d.municipality_id,COALESCE(m.municipality_name,"Province-wide") municipality_name,d.date_occurred,d.casualties,d.damages FROM historical_disasters d LEFT JOIN municipalities m ON m.id=d.municipality_id WHERE d.id=?');$s->execute([$id]);$row=$s->fetch();return $row?$this->cast($row):null;
    }
    public function create(array $d): int
    {
        $s=$this->db->prepare('INSERT INTO historical_disasters (title,disaster_type,description,municipality_id,date_occurred,casualties,damages) VALUES (?,?,?,?,?,?,?)');$s->execute([$d['title'],$d['disaster_type'],$d['description'],$d['municipality_id'],$d['date_occurred'],$d['casualties'],$d['damages']]);return (int)$this->db->lastInsertId();
    }
    public function update(int $id,array $d): void
    {
        $this->db->prepare('UPDATE historical_disasters SET title=?,disaster_type=?,description=?,municipality_id=?,date_occurred=?,casualties=?,damages=? WHERE id=?')->execute([$d['title'],$d['disaster_type'],$d['description'],$d['municipality_id'],$d['date_occurred'],$d['casualties'],$d['damages'],$id]);
    }
    public function delete(int $id): void { $this->db->prepare('DELETE FROM historical_disasters WHERE id=?')->execute([$id]); }
    private function cast(array $row): array { $row['id']=(int)$row['id'];$row['municipality_id']=$row['municipality_id']===null?null:(int)$row['municipality_id'];$row['casualties']=(int)$row['casualties'];$row['damages']=(float)$row['damages'];return $row; }
}
