<?php
require_once dirname(__DIR__) . '/bootstrap.php';

use App\Core\Database;

$db = Database::connection();

$lgus = [
    ['Alfonso', 'Cavite municipality', 14.1408, 120.8536],
    ['Amadeo', 'Cavite municipality', 14.1706, 120.9236],
    ['Bacoor City', 'Cavite component city', 14.4590, 120.9290],
    ['Carmona City', 'Cavite component city', 14.3132, 121.0576],
    ['Cavite City', 'Cavite component city', 14.4837, 120.8988],
    ['Dasmarinas City', 'Cavite component city', 14.3294, 120.9367],
    ['General Emilio Aguinaldo', 'Cavite municipality', 14.1842, 120.7958],
    ['General Trias City', 'Cavite component city', 14.3869, 120.8816],
    ['General Mariano Alvarez', 'Cavite municipality', 14.3050, 121.0033],
    ['Imus City', 'Cavite component city', 14.4297, 120.9367],
    ['Indang', 'Cavite municipality', 14.1953, 120.8769],
    ['Kawit', 'Cavite municipality', 14.4443, 120.9015],
    ['Magallanes', 'Cavite municipality', 14.1883, 120.7575],
    ['Maragondon', 'Cavite municipality', 14.2733, 120.7378],
    ['Mendez', 'Cavite municipality', 14.1286, 120.9058],
    ['Naic', 'Cavite municipality', 14.3181, 120.7661],
    ['Noveleta', 'Cavite municipality', 14.4292, 120.8799],
    ['Rosario', 'Cavite municipality', 14.4140, 120.8570],
    ['Silang', 'Cavite municipality', 14.2157, 120.9714],
    ['Tagaytay City', 'Cavite component city', 14.1153, 120.9622],
    ['Tanza', 'Cavite municipality', 14.3940, 120.8530],
    ['Ternate', 'Cavite municipality', 14.2897, 120.7168],
    ['Trece Martires City', 'Cavite component city', 14.2822, 120.8671],
];

$statement = $db->prepare(
    'INSERT INTO municipalities (municipality_name,description,center_lat,center_lng,status)
     VALUES (?,?,?,?, "active")
     ON DUPLICATE KEY UPDATE
       description = VALUES(description),
       center_lat = VALUES(center_lat),
       center_lng = VALUES(center_lng),
       status = "active"'
);

$db->beginTransaction();
try {
    $db->exec("DELETE FROM municipalities WHERE municipality_name = 'Sample Municipality'");
} catch (PDOException) {
    // Keep the sample row if existing historical records or other restricted data still reference it.
}
foreach ($lgus as [$name, $description, $lat, $lng]) {
    $statement->execute([$name, $description, $lat, $lng]);
}

$aliases = [
    'City of Bacoor' => 'Bacoor City',
    'City of Dasmarinas' => 'Dasmarinas City',
    'City of General Trias' => 'General Trias City',
    'City of Imus' => 'Imus City',
];
$referenceTables = ['users','hazards','alerts','weather_updates','safe_zones','evacuation_centers','evacuation_routes','historical_disasters'];
$findId = $db->prepare('SELECT id FROM municipalities WHERE municipality_name = ?');
foreach ($aliases as $duplicateName => $canonicalName) {
    $findId->execute([$duplicateName]);
    $duplicateId = $findId->fetchColumn();
    $findId->execute([$canonicalName]);
    $canonicalId = $findId->fetchColumn();
    if (!$duplicateId || !$canonicalId || (int) $duplicateId === (int) $canonicalId) continue;
    foreach ($referenceTables as $table) {
        $db->prepare("UPDATE `$table` SET municipality_id = ? WHERE municipality_id = ?")->execute([$canonicalId, $duplicateId]);
    }
    $db->prepare('DELETE FROM municipalities WHERE id = ?')->execute([$duplicateId]);
}
$db->commit();

echo 'Seeded ' . count($lgus) . " Cavite LGUs.\n";
