<?php
namespace App\Models;

final class Municipality extends BaseModel
{
    public function all(bool $activeOnly=false): array
    {
        $sql='SELECT id,municipality_name,description,status,created_at,updated_at FROM municipalities'.($activeOnly?' WHERE status="active"':'').' ORDER BY municipality_name';
        return $this->db->query($sql)->fetchAll();
    }
    public function find(int $id): ?array
    {
        $s=$this->db->prepare('SELECT id,municipality_name,description,status,created_at,updated_at FROM municipalities WHERE id=?');$s->execute([$id]);return $s->fetch()?:null;
    }
    public function nameExists(string $name,?int $exceptId=null): bool
    {
        $sql='SELECT 1 FROM municipalities WHERE LOWER(municipality_name)=LOWER(?)';$values=[$name];if($exceptId){$sql.=' AND id<>?';$values[]=$exceptId;}$s=$this->db->prepare($sql);$s->execute($values);return (bool)$s->fetchColumn();
    }
    public function create(array $data): int
    {
        $s=$this->db->prepare('INSERT INTO municipalities (municipality_name,description,status) VALUES (?,?,?)');$s->execute([$data['municipality_name'],$data['description'],$data['status']]);return (int)$this->db->lastInsertId();
    }
    public function update(int $id,array $data): bool
    {
        $s=$this->db->prepare('UPDATE municipalities SET municipality_name=?,description=?,status=? WHERE id=?');$s->execute([$data['municipality_name'],$data['description'],$data['status'],$id]);return $s->rowCount()>0;
    }
    public function delete(int $id): bool
    {
        $s=$this->db->prepare('DELETE FROM municipalities WHERE id=?');$s->execute([$id]);return $s->rowCount()>0;
    }
}
