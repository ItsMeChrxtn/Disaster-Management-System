<?php
namespace App\Models;

use App\Core\Schema;
use PDO;

/**
 * PDRRMO <-> MDRRMO/CDRRMO coordination channel. Every municipality has one channel;
 * province broadcasts (municipality_id NULL) appear in every channel.
 */
final class CoordinationMessage extends BaseModel
{
    public const CATEGORIES=['advisory','directive','situation_report','request','response','general'];
    public const PRIORITIES=['normal','urgent','critical'];

    public function __construct()
    {
        parent::__construct();
        Schema::ensureTable('lgu_messages','CREATE TABLE IF NOT EXISTS lgu_messages (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            municipality_id BIGINT UNSIGNED NULL,
            sender_id BIGINT UNSIGNED NOT NULL,
            direction ENUM("to_lgu","to_province") NOT NULL,
            category ENUM("advisory","directive","situation_report","request","response","general") NOT NULL DEFAULT "general",
            priority ENUM("normal","urgent","critical") NOT NULL DEFAULT "normal",
            subject VARCHAR(180) NOT NULL,
            body TEXT NOT NULL,
            requires_ack TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            KEY idx_lgu_messages_channel (municipality_id,created_at),
            CONSTRAINT fk_lgu_message_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
            CONSTRAINT fk_lgu_message_sender FOREIGN KEY (sender_id) REFERENCES users(id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
        Schema::ensureTable('lgu_message_acks','CREATE TABLE IF NOT EXISTS lgu_message_acks (
            message_id BIGINT UNSIGNED NOT NULL,
            municipality_id BIGINT UNSIGNED NOT NULL,
            user_id BIGINT UNSIGNED NOT NULL,
            acknowledged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (message_id,municipality_id),
            CONSTRAINT fk_lgu_ack_message FOREIGN KEY (message_id) REFERENCES lgu_messages(id) ON DELETE CASCADE,
            CONSTRAINT fk_lgu_ack_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
            CONSTRAINT fk_lgu_ack_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
        Schema::ensureTable('lgu_channel_reads','CREATE TABLE IF NOT EXISTS lgu_channel_reads (
            user_id BIGINT UNSIGNED NOT NULL,
            municipality_id BIGINT UNSIGNED NOT NULL,
            last_read_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id,municipality_id),
            CONSTRAINT fk_lgu_read_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            CONSTRAINT fk_lgu_read_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    }

    public static function officeFor(?string $municipalityName): string
    {
        return $municipalityName!==null&&stripos($municipalityName,'city')!==false?'CDRRMO':'MDRRMO';
    }

    /** One row per active municipality (or only $onlyMunicipality) with last message, unread and pending acknowledgements. */
    public function channels(int $userId,string $role,?int $onlyMunicipality=null): array
    {
        $incoming=$role==='admin'?'to_province':'to_lgu';
        $sql='SELECT m.id municipality_id,m.municipality_name,
                (SELECT COUNT(*) FROM users u WHERE u.municipality_id=m.id AND u.role="subadmin" AND u.status="active") officers,
                (SELECT MAX(x.id) FROM lgu_messages x WHERE x.municipality_id=m.id OR x.municipality_id IS NULL) last_id,
                (SELECT COUNT(*) FROM lgu_messages x WHERE (x.municipality_id=m.id OR x.municipality_id IS NULL) AND x.direction=:incoming AND x.id>IFNULL(r.last_read_id,0)) unread,
                (SELECT COUNT(*) FROM lgu_messages x WHERE (x.municipality_id=m.id OR x.municipality_id IS NULL) AND x.direction="to_lgu" AND x.requires_ack=1 AND NOT EXISTS (SELECT 1 FROM lgu_message_acks a WHERE a.message_id=x.id AND a.municipality_id=m.id)) pending_ack
              FROM municipalities m LEFT JOIN lgu_channel_reads r ON r.municipality_id=m.id AND r.user_id=:uid WHERE m.status="active"';
        $params=['incoming'=>$incoming,'uid'=>$userId];
        if($onlyMunicipality){$sql.=' AND m.id=:mid';$params['mid']=$onlyMunicipality;}
        $sql.=' ORDER BY m.municipality_name';
        $s=$this->db->prepare($sql);$s->execute($params);$rows=$s->fetchAll();
        $lastIds=array_values(array_filter(array_map(fn($r)=>(int)$r['last_id'],$rows)));$last=[];
        if($lastIds){$s=$this->db->prepare('SELECT x.id,x.subject,x.direction,x.priority,x.created_at,x.municipality_id FROM lgu_messages x WHERE x.id IN ('.implode(',',array_fill(0,count($lastIds),'?')).')');$s->execute($lastIds);foreach($s->fetchAll() as $m)$last[(int)$m['id']]=$m;}
        return array_map(fn($r)=>['municipality_id'=>(int)$r['municipality_id'],'municipality_name'=>$r['municipality_name'],'office'=>self::officeFor($r['municipality_name']),'officers'=>(int)$r['officers'],'unread'=>(int)$r['unread'],'pending_ack'=>(int)$r['pending_ack'],'last_message'=>isset($last[(int)$r['last_id']])?$this->castLast($last[(int)$r['last_id']]):null],$rows);
    }

    /** Messages for one municipality channel (including province broadcasts), oldest first. */
    public function thread(int $municipalityId,int $limit=200): array
    {
        $s=$this->db->prepare('SELECT x.id,x.municipality_id,x.direction,x.category,x.priority,x.subject,x.body,x.requires_ack,x.created_at,u.fullname sender_name,u.role sender_role,sm.municipality_name sender_municipality,
                a.acknowledged_at,au.fullname acknowledged_by
            FROM lgu_messages x JOIN users u ON u.id=x.sender_id LEFT JOIN municipalities sm ON sm.id=u.municipality_id
            LEFT JOIN lgu_message_acks a ON a.message_id=x.id AND a.municipality_id=:ack_mid LEFT JOIN users au ON au.id=a.user_id
            WHERE x.municipality_id=:mid OR x.municipality_id IS NULL ORDER BY x.id DESC LIMIT '.(int)$limit);
        $s->execute(['ack_mid'=>$municipalityId,'mid'=>$municipalityId]);
        return array_reverse(array_map([$this,'cast'],$s->fetchAll()));
    }

    /** Province broadcasts with how many municipalities acknowledged each. */
    public function broadcasts(int $limit=100): array
    {
        $s=$this->db->query('SELECT x.id,x.municipality_id,x.direction,x.category,x.priority,x.subject,x.body,x.requires_ack,x.created_at,u.fullname sender_name,u.role sender_role,NULL sender_municipality,NULL acknowledged_at,NULL acknowledged_by,
                (SELECT COUNT(*) FROM lgu_message_acks a WHERE a.message_id=x.id) ack_count
            FROM lgu_messages x JOIN users u ON u.id=x.sender_id WHERE x.municipality_id IS NULL ORDER BY x.id DESC LIMIT '.(int)$limit);
        return array_reverse(array_map(function($row){$cast=$this->cast($row);$cast['ack_count']=(int)$row['ack_count'];return $cast;},$s->fetchAll()));
    }

    public function find(int $id): ?array
    {
        $s=$this->db->prepare('SELECT x.*,u.fullname sender_name FROM lgu_messages x JOIN users u ON u.id=x.sender_id WHERE x.id=?');$s->execute([$id]);return $s->fetch()?:null;
    }

    public function create(?int $municipalityId,int $senderId,string $direction,array $d): int
    {
        $s=$this->db->prepare('INSERT INTO lgu_messages (municipality_id,sender_id,direction,category,priority,subject,body,requires_ack) VALUES (?,?,?,?,?,?,?,?)');
        $s->execute([$municipalityId,$senderId,$direction,$d['category'],$d['priority'],$d['subject'],$d['body'],$d['requires_ack']?1:0]);
        return (int)$this->db->lastInsertId();
    }

    public function acknowledge(int $messageId,int $municipalityId,int $userId): void
    {
        $this->db->prepare('INSERT IGNORE INTO lgu_message_acks (message_id,municipality_id,user_id) VALUES (?,?,?)')->execute([$messageId,$municipalityId,$userId]);
    }

    public function markChannelRead(int $userId,int $municipalityId): void
    {
        $s=$this->db->prepare('SELECT COALESCE(MAX(id),0) FROM lgu_messages WHERE municipality_id=? OR municipality_id IS NULL');$s->execute([$municipalityId]);$last=(int)$s->fetchColumn();
        $this->db->prepare('INSERT INTO lgu_channel_reads (user_id,municipality_id,last_read_id) VALUES (?,?,?) ON DUPLICATE KEY UPDATE last_read_id=GREATEST(last_read_id,VALUES(last_read_id))')->execute([$userId,$municipalityId,$last]);
    }

    public function activeMunicipalities(array $ids): array
    {
        if(!$ids)return [];
        $s=$this->db->prepare('SELECT id,municipality_name FROM municipalities WHERE status="active" AND id IN ('.implode(',',array_fill(0,count($ids),'?')).')');$s->execute(array_values($ids));
        return $s->fetchAll(PDO::FETCH_KEY_PAIR);
    }

    private function castLast(array $row): array
    {
        return ['id'=>(int)$row['id'],'subject'=>$row['subject'],'direction'=>$row['direction'],'priority'=>$row['priority'],'created_at'=>$row['created_at'],'is_broadcast'=>$row['municipality_id']===null];
    }
    private function cast(array $row): array
    {
        $row['id']=(int)$row['id'];$row['municipality_id']=$row['municipality_id']===null?null:(int)$row['municipality_id'];$row['requires_ack']=(bool)$row['requires_ack'];$row['is_broadcast']=$row['municipality_id']===null;
        $row['sender_office']=$row['sender_role']==='admin'?'PDRRMO':self::officeFor($row['sender_municipality']??null);
        return $row;
    }
}
