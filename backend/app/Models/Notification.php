<?php
namespace App\Models;

use PDO;

final class Notification extends BaseModel
{
    public function history(int $userId): array
    {
        $s=$this->db->prepare('SELECT id,notification_type,title,message,is_read,read_at,created_at FROM notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 100');
        $s->execute([$userId]);$rows=$s->fetchAll();foreach($rows as &$row)$row['is_read']=(bool)$row['is_read'];return $rows;
    }
    public function unreadCount(int $userId): int { $s=$this->db->prepare('SELECT COUNT(*) FROM notifications WHERE user_id=? AND is_read=0');$s->execute([$userId]);return (int)$s->fetchColumn(); }
    public function markRead(int $id,int $userId): void { $this->db->prepare('UPDATE notifications SET is_read=1,read_at=UTC_TIMESTAMP() WHERE id=? AND user_id=?')->execute([$id,$userId]); }

    /** Insert one notification for every active user with the given role (optionally scoped to a municipality). */
    public function notifyRole(string $role,?int $municipalityId,string $type,string $title,string $message): void
    {
        $sql='SELECT id FROM users WHERE role=? AND status="active"';$values=[$role];
        if($municipalityId!==null){$sql.=' AND municipality_id=?';$values[]=$municipalityId;}
        $s=$this->db->prepare($sql);$s->execute($values);$ids=$s->fetchAll(PDO::FETCH_COLUMN);
        if(!$ids)return;
        $insert=$this->db->prepare('INSERT INTO notifications (user_id,notification_type,title,message) VALUES (?,?,?,?)');
        foreach($ids as $userId)$insert->execute([$userId,$type,$title,$message]);
    }
}
