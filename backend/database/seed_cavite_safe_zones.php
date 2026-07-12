<?php
require_once dirname(__DIR__) . '/bootstrap.php';

use App\Core\Database;

$db = Database::connection();

// Civic/open-ground safe-zone seed data for map and routing use.
// Coordinates are near LGU civic centers or public open grounds and should be verified by local DRRMO teams before
// being treated as official emergency assembly points.
$safeZones = [
    ['Bacoor City', 'Bacoor City Hall Open Grounds', 'Bacoor Government Center, Bacoor City, Cavite', 14.4590000, 120.9290000, 800, 'Open civic grounds near the city government center.'],
    ['Imus City', 'Imus City Plaza Safe Zone', 'Imus City Plaza, Imus City, Cavite', 14.4297000, 120.9367000, 700, 'Public plaza/open assembly area in the city center.'],
    ['Dasmarinas City', 'Dasmarinas City Hall Grounds Safe Zone', 'Dasmarinas City Hall area, Dasmarinas City, Cavite', 14.3294000, 120.9367000, 1000, 'Civic grounds near the city hall area.'],
    ['General Trias City', 'General Trias City Plaza Safe Zone', 'General Trias City Plaza, General Trias City, Cavite', 14.3869000, 120.8816000, 650, 'Public plaza/open assembly area near the city center.'],
    ['Trece Martires City', 'Provincial Capitol Grounds Safe Zone', 'Cavite Provincial Capitol Grounds, Trece Martires City, Cavite', 14.2822000, 120.8671000, 1200, 'Open provincial government grounds for assembly planning.'],
    ['Tagaytay City', 'Tagaytay City Hall Grounds Safe Zone', 'Tagaytay City Hall area, Tagaytay City, Cavite', 14.1153000, 120.9622000, 600, 'Civic grounds in Tagaytay City.'],
    ['Tanza', 'Tanza Municipal Plaza Safe Zone', 'Tanza Municipal Plaza, Tanza, Cavite', 14.3940000, 120.8530000, 500, 'Municipal plaza/open assembly area.'],
    ['Silang', 'Silang Municipal Plaza Safe Zone', 'Silang Municipal Plaza, Silang, Cavite', 14.2157000, 120.9714000, 550, 'Municipal plaza/open assembly area.'],
    ['Naic', 'Naic Municipal Plaza Safe Zone', 'Naic Municipal Plaza, Naic, Cavite', 14.3181000, 120.7661000, 450, 'Municipal plaza/open assembly area.'],
    ['Rosario', 'Rosario Municipal Plaza Safe Zone', 'Rosario Municipal Plaza, Rosario, Cavite', 14.4140000, 120.8570000, 450, 'Municipal plaza/open assembly area.'],
];

$municipalityIds = [];
$municipalityStatement = $db->query('SELECT id, municipality_name FROM municipalities WHERE status = "active"');
foreach ($municipalityStatement->fetchAll() as $row) {
    $municipalityIds[$row['municipality_name']] = (int) $row['id'];
}

$find = $db->prepare('SELECT id FROM safe_zones WHERE municipality_id = ? AND safezone_name = ? LIMIT 1');
$insert = $db->prepare(
    'INSERT INTO safe_zones (safezone_name,municipality_id,address,latitude,longitude,capacity,description,status)
     VALUES (?,?,?,?,?,?,?,"active")'
);
$update = $db->prepare(
    'UPDATE safe_zones
     SET address = ?, latitude = ?, longitude = ?, capacity = ?, description = ?, status = "active"
     WHERE id = ?'
);

$db->beginTransaction();
$seeded = 0;
foreach ($safeZones as [$municipality, $name, $address, $lat, $lng, $capacity, $description]) {
    $municipalityId = $municipalityIds[$municipality] ?? null;
    if (!$municipalityId) {
        throw new RuntimeException("Municipality not found for safe-zone seed: {$municipality}");
    }

    $find->execute([$municipalityId, $name]);
    $existingId = $find->fetchColumn();
    if ($existingId) {
        $update->execute([$address, $lat, $lng, $capacity, $description, $existingId]);
    } else {
        $insert->execute([$name, $municipalityId, $address, $lat, $lng, $capacity, $description]);
    }
    $seeded++;
}
$db->commit();

echo "Seeded {$seeded} Cavite safe zones.\n";
