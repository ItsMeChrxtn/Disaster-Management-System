<?php
require dirname(__DIR__).'/bootstrap.php';
use App\Core\Database;
$db=Database::connection();
$db->exec("INSERT IGNORE INTO municipalities (id,municipality_name,description,center_lat,center_lng) VALUES (1,'Sample Municipality','Initial municipality record',14.5995000,120.9842000)");
$email=$argv[1]??'admin@example.gov.ph'; $password=$argv[2]??bin2hex(random_bytes(6));
$s=$db->prepare('INSERT INTO users (fullname,email,password,role,status) VALUES (?,?,?,"admin","active") ON DUPLICATE KEY UPDATE password=VALUES(password),role="admin",status="active"');
$s->execute(['PDRRMO Administrator',$email,password_hash($password,PASSWORD_DEFAULT)]);
echo "Admin: $email\nPassword: $password\nChange this password after first login.\n";
