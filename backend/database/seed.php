<?php
require dirname(__DIR__).'/bootstrap.php';
use App\Core\Database;
$db=Database::connection();
require __DIR__.'/seed_cavite_lgus.php';
require __DIR__.'/seed_cavite_safe_zones.php';
require __DIR__.'/seed_cavite_evacuation_centers.php';
$email=$argv[1]??'admin@example.gov.ph'; $password=$argv[2]??bin2hex(random_bytes(6));
$s=$db->prepare('INSERT INTO users (fullname,email,password,role,status) VALUES (?,?,?,"admin","active") ON DUPLICATE KEY UPDATE password=VALUES(password),role="admin",status="active"');
$s->execute(['PDRRMO Administrator',$email,password_hash($password,PASSWORD_DEFAULT)]);
require __DIR__.'/seed_cavite_hazards.php';
echo "Admin: $email\nPassword: $password\nChange this password after first login.\n";
