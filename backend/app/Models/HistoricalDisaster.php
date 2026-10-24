<?php
namespace App\Models;

use App\Core\Schema;

final class HistoricalDisaster extends BaseModel
{
    private const FIELDS='d.id,d.title,d.disaster_type,d.event_name,d.description,d.municipality_id,COALESCE(m.municipality_name,"Province-wide") municipality_name,d.date_occurred,d.casualties,d.injured,d.evacuated_families,d.affected_barangays,d.affected_barangay_count,d.damages,d.source';

    public function __construct()
    {
        parent::__construct();
        // Revision 3 (Oct 2026): impact details per record. Self-migrating so the live DB needs no manual import.
        Schema::ensureColumn('historical_disasters','event_name','VARCHAR(160) NULL AFTER disaster_type');
        Schema::ensureColumn('historical_disasters','injured','INT UNSIGNED NOT NULL DEFAULT 0 AFTER casualties');
        Schema::ensureColumn('historical_disasters','evacuated_families','INT UNSIGNED NOT NULL DEFAULT 0 AFTER injured');
        Schema::ensureColumn('historical_disasters','affected_barangays','TEXT NULL AFTER evacuated_families');
        Schema::ensureColumn('historical_disasters','affected_barangay_count','INT UNSIGNED NOT NULL DEFAULT 0 AFTER affected_barangays');
        Schema::ensureColumn('historical_disasters','source','VARCHAR(255) NULL AFTER damages');
    }

    public function all(array $filters=[]): array
    {
        $sql='SELECT '.self::FIELDS.' FROM historical_disasters d LEFT JOIN municipalities m ON m.id=d.municipality_id';
        $where=[];$values=[];
        if(!empty($filters['search'])){$where[]='(d.title LIKE ? OR d.description LIKE ? OR d.disaster_type LIKE ? OR d.event_name LIKE ? OR d.affected_barangays LIKE ?)';$term='%'.$filters['search'].'%';array_push($values,$term,$term,$term,$term,$term);}
        if(!empty($filters['disaster_type'])){$where[]='d.disaster_type=?';$values[]=$filters['disaster_type'];}
        if(!empty($filters['municipality_id'])){$where[]='d.municipality_id=?';$values[]=$filters['municipality_id'];}
        if(!empty($filters['date_from'])){$where[]='d.date_occurred>=?';$values[]=$filters['date_from'];}
        if(!empty($filters['date_to'])){$where[]='d.date_occurred<=?';$values[]=$filters['date_to'];}
        if($where)$sql.=' WHERE '.implode(' AND ',$where);
        $sql.=' ORDER BY d.date_occurred DESC,d.id DESC LIMIT 1000';
        $s=$this->db->prepare($sql);$s->execute($values);return array_map([$this,'cast'],$s->fetchAll());
    }
    public function find(int $id): ?array
    {
        $s=$this->db->prepare('SELECT '.self::FIELDS.' FROM historical_disasters d LEFT JOIN municipalities m ON m.id=d.municipality_id WHERE d.id=?');$s->execute([$id]);$row=$s->fetch();return $row?$this->cast($row):null;
    }
    public function create(array $d): int
    {
        $s=$this->db->prepare('INSERT INTO historical_disasters (title,disaster_type,event_name,description,municipality_id,date_occurred,casualties,injured,evacuated_families,affected_barangays,affected_barangay_count,damages,source) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)');
        $s->execute($this->values($d));return (int)$this->db->lastInsertId();
    }
    public function update(int $id,array $d): void
    {
        $this->db->prepare('UPDATE historical_disasters SET title=?,disaster_type=?,event_name=?,description=?,municipality_id=?,date_occurred=?,casualties=?,injured=?,evacuated_families=?,affected_barangays=?,affected_barangay_count=?,damages=?,source=? WHERE id=?')->execute([...$this->values($d),$id]);
    }
    public function delete(int $id): void { $this->db->prepare('DELETE FROM historical_disasters WHERE id=?')->execute([$id]); }

    private function values(array $d): array
    {
        return [$d['title'],$d['disaster_type'],$d['event_name']??null,$d['description'],$d['municipality_id'],$d['date_occurred'],$d['casualties'],$d['injured']??0,$d['evacuated_families']??0,$d['affected_barangays']??null,$d['affected_barangay_count']??0,$d['damages'],$d['source']??null];
    }
    private function cast(array $row): array
    {
        $row['id']=(int)$row['id'];$row['municipality_id']=$row['municipality_id']===null?null:(int)$row['municipality_id'];
        foreach(['casualties','injured','evacuated_families','affected_barangay_count'] as $key)$row[$key]=(int)($row[$key]??0);
        $row['damages']=(float)$row['damages'];
        $row['barangay_list']=array_values(array_filter(array_map('trim',preg_split('/[\n;]+/',(string)($row['affected_barangays']??'')))));
        return $row;
    }
}
