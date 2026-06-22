<?php
namespace App\Models;

final class Alert extends BaseModel
{
    private const SELECT='SELECT a.id,a.title,a.alert_type,a.alert_level,a.message,a.municipality_id,a.created_by,a.status,a.sent_at,a.created_at,a.updated_at,m.municipality_name,u.fullname created_by_name FROM alerts a LEFT JOIN municipalities m ON m.id=a.municipality_id JOIN users u ON u.id=a.created_by';
    public function publicSent(): array { return $this->db->query(self::SELECT.' WHERE a.status="sent" ORDER BY a.sent_at DESC LIMIT 100')->fetchAll(); }
    public function managed(?int $municipalityId): array { $sql=self::SELECT.' WHERE a.status<>"deleted"';$values=[];if($municipalityId){$sql.=' AND a.municipality_id=?';$values[]=$municipalityId;}$sql.=' ORDER BY a.created_at DESC LIMIT 250';$s=$this->db->prepare($sql);$s->execute($values);return $s->fetchAll(); }
    public function find(int $id): ?array { $s=$this->db->prepare(self::SELECT.' WHERE a.id=?');$s->execute([$id]);return $s->fetch()?:null; }
    public function create(array $d,int $userId): int { $s=$this->db->prepare('INSERT INTO alerts (title,alert_type,alert_level,message,municipality_id,created_by,status) VALUES (?,?,?,?,?,?,"draft")');$s->execute([$d['title'],$d['alert_type'],$d['alert_level'],$d['message'],$d['municipality_id'],$userId]);return (int)$this->db->lastInsertId(); }
    public function update(int $id,array $d): void { $this->db->prepare('UPDATE alerts SET title=?,alert_type=?,alert_level=?,message=?,municipality_id=? WHERE id=?')->execute([$d['title'],$d['alert_type'],$d['alert_level'],$d['message'],$d['municipality_id'],$id]); }
    public function setStatus(int $id,string $status): void { $this->db->prepare('UPDATE alerts SET status=?,sent_at=IF(?="sent",UTC_TIMESTAMP(),sent_at) WHERE id=?')->execute([$status,$status,$id]); }
    public function history(int $userId,?int $municipalityId): array
    {
        $s=$this->db->prepare('SELECT a.id,a.title,a.alert_type,a.alert_level,a.message,a.municipality_id,a.sent_at,a.created_at,m.municipality_name,(r.read_at IS NOT NULL) is_read,r.read_at FROM alerts a LEFT JOIN municipalities m ON m.id=a.municipality_id LEFT JOIN alert_reads r ON r.alert_id=a.id AND r.user_id=? WHERE a.status="sent" AND (a.municipality_id IS NULL OR a.municipality_id=?) ORDER BY a.sent_at DESC LIMIT 250');$s->execute([$userId,$municipalityId??0]);$rows=$s->fetchAll();foreach($rows as &$row)$row['is_read']=(bool)$row['is_read'];return $rows;
    }
    public function unreadCount(int $userId,?int $municipalityId): int { $s=$this->db->prepare('SELECT COUNT(*) FROM alerts a LEFT JOIN alert_reads r ON r.alert_id=a.id AND r.user_id=? WHERE a.status="sent" AND (a.municipality_id IS NULL OR a.municipality_id=?) AND r.alert_id IS NULL');$s->execute([$userId,$municipalityId??0]);return (int)$s->fetchColumn(); }
    public function markRead(int $alertId,int $userId): void { $this->db->prepare('INSERT INTO alert_reads (alert_id,user_id) VALUES (?,?) ON DUPLICATE KEY UPDATE read_at=VALUES(read_at)')->execute([$alertId,$userId]); }
}

