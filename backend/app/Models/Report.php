<?php
namespace App\Models;

final class Report extends BaseModel
{
    public function all(?int $generatedBy=null): array
    {
        $sql='SELECT r.id,r.report_type,r.generated_by,r.generated_at,r.file_path,u.fullname generated_by_name FROM reports r JOIN users u ON u.id=r.generated_by';$values=[];if($generatedBy){$sql.=' WHERE r.generated_by=?';$values[]=$generatedBy;}$sql.=' ORDER BY r.generated_at DESC LIMIT 250';$s=$this->db->prepare($sql);$s->execute($values);$rows=$s->fetchAll();foreach($rows as &$row)$row['format']=strtolower(pathinfo($row['file_path'],PATHINFO_EXTENSION));return $rows;
    }
    public function find(int $id): ?array { $s=$this->db->prepare('SELECT r.*,u.fullname generated_by_name FROM reports r JOIN users u ON u.id=r.generated_by WHERE r.id=?');$s->execute([$id]);return $s->fetch()?:null; }
    public function create(string $type,int $userId,string $path): int { $s=$this->db->prepare('INSERT INTO reports (report_type,generated_by,file_path) VALUES (?,?,?)');$s->execute([$type,$userId,$path]);return (int)$this->db->lastInsertId(); }
    public function delete(int $id): void { $this->db->prepare('DELETE FROM reports WHERE id=?')->execute([$id]); }
}

