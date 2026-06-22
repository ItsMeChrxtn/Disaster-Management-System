<?php
namespace App\Models;

final class User extends BaseModel
{
    private const PUBLIC_COLUMNS='u.id,u.municipality_id,u.fullname,u.email,u.phone,u.address,u.barangay,u.role,u.status,u.created_at,u.updated_at,m.municipality_name';

    public function findByEmail(string $email): ?array { $s=$this->db->prepare('SELECT * FROM users WHERE email=? LIMIT 1');$s->execute([$email]);return $s->fetch()?:null; }
    public function create(array $d): int { $s=$this->db->prepare('INSERT INTO users (municipality_id,fullname,email,password,phone,address,barangay,role,status) VALUES (?,?,?,?,?,?,?,"resident","active")');$s->execute([$d['municipality_id']?:null,$d['fullname'],strtolower($d['email']),password_hash($d['password'],PASSWORD_DEFAULT),$d['phone']??null,$d['address']??null,$d['barangay']??null]);return (int)$this->db->lastInsertId(); }
    public function publicById(int $id): ?array { return $this->findManaged($id); }
    public function managedList(?int $municipalityId=null): array
    {
        $sql='SELECT '.self::PUBLIC_COLUMNS.' FROM users u LEFT JOIN municipalities m ON m.id=u.municipality_id';$values=[];
        if($municipalityId!==null){$sql.=' WHERE u.municipality_id=? AND u.role="resident" AND u.status<>"deleted"';$values[]=$municipalityId;}$sql.=' ORDER BY u.created_at DESC LIMIT 500';$s=$this->db->prepare($sql);$s->execute($values);return $s->fetchAll();
    }
    public function findManaged(int $id): ?array { $s=$this->db->prepare('SELECT '.self::PUBLIC_COLUMNS.' FROM users u LEFT JOIN municipalities m ON m.id=u.municipality_id WHERE u.id=?');$s->execute([$id]);return $s->fetch()?:null; }
    public function managementCreate(array $d): int
    {
        $s=$this->db->prepare('INSERT INTO users (municipality_id,fullname,email,password,phone,address,barangay,role,status) VALUES (?,?,?,?,?,?,?,? ,"active")');$s->execute([$d['municipality_id'],$d['fullname'],$d['email'],password_hash($d['password'],PASSWORD_DEFAULT),$d['phone'],$d['address'],$d['barangay'],$d['role']]);return (int)$this->db->lastInsertId();
    }
    public function managementUpdate(int $id,array $d): void
    {
        $values=[$d['municipality_id'],$d['fullname'],$d['email'],$d['phone'],$d['address'],$d['barangay'],$d['role']];$sql='UPDATE users SET municipality_id=?,fullname=?,email=?,phone=?,address=?,barangay=?,role=?';if($d['password']!==''){$sql.=',password=?';$values[]=password_hash($d['password'],PASSWORD_DEFAULT);}$sql.=' WHERE id=?';$values[]=$id;$this->db->prepare($sql)->execute($values);
    }
    public function setStatus(int $id,string $status): void { $this->db->prepare('UPDATE users SET status=? WHERE id=?')->execute([$status,$id]); }
    public function revokeSessions(int $id): void { $this->db->prepare('UPDATE user_sessions SET revoked_at=UTC_TIMESTAMP() WHERE user_id=? AND revoked_at IS NULL')->execute([$id]); }
}

