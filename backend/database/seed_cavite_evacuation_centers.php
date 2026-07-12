<?php
require_once dirname(__DIR__) . '/bootstrap.php';

use App\Core\Database;

$db = Database::connection();

// Source notes:
// - DILG SubayBAYAN project pages: https://t-subaybayan.dilg.gov.ph/projects/{id}
// - PIA Imus completion notice: https://mirror.pia.gov.ph/news/2022/04/07/new-multi-purpose-evacuation-center-in-imus-city-completed
// - Coordinates were resolved from the source address/barangay using OpenStreetMap Nominatim when exact coordinates
//   were not published by the source. Capacity uses the source-listed beneficiary/person count when available and
//   should be field-verified before operational use.
$centers = [
    ['Alfonso', 'Alfonso Multi-Purpose Evacuation Center', 'Rodeo Hills, Buck Estate, Alfonso, Cavite', null, 0, 'available', 14.0775856, 120.8578465, 'DPWH/Multi-purpose evacuation center reference'],
    ['Carmona City', 'Lantic Evacuation Facility', 'Lantic Barangay Hall Compound, Macha Street, Barangay Lantic, Carmona, Cavite', null, 19462, 'available', 14.2970587, 121.0498446, 'DILG SubayBAYAN project 20660'],
    ['Carmona City', 'Mabuhay Evacuation Center', 'Barangay Mabuhay Government Compound, Mapalad Street, Mabuhay, Carmona, Cavite', null, 9633, 'available', 14.3116136, 121.0498536, 'DILG SubayBAYAN project 37507'],
    ['Carmona City', 'Carmona Elementary School Evacuation Center', 'Carmona Elementary School, Rosario Street, Barangay 8, Carmona, Cavite', null, 0, 'available', 14.3135008, 121.0537881, 'DILG SubayBAYAN project 43592'],
    ['Carmona City', 'Cabilang Baybay Elementary School Evacuation Center', 'Cabilang Baybay Elementary School, San Mateo Street, Cabilang Baybay, Carmona, Cavite', null, 0, 'available', 14.3179287, 121.0495538, 'DILG SubayBAYAN project 43592'],
    ['Carmona City', 'Milagrosa Main Elementary School Evacuation Center', 'Milagrosa Main Elementary School, Milagrosa, Carmona, Cavite', null, 0, 'available', 14.3075448, 121.0485800, 'DILG SubayBAYAN project 43592'],
    ['Carmona City', 'Lantic Elementary School Evacuation Center', 'Lantic Elementary School, A. Macha Street, Lantic, Carmona, Cavite', null, 0, 'available', 14.2978480, 121.0498785, 'DILG SubayBAYAN project 43592'],
    ['Carmona City', 'Paligawan Matanda Elementary School Evacuation Center', 'Paligawan Matanda Elementary School, Paligawan Road, Paligawan Matanda, Carmona, Cavite', null, 0, 'available', 14.2645226, 121.0306125, 'DILG SubayBAYAN project 43592'],
    ['Cavite City', 'Barangay 28 Sta. Cruz Evacuation Center', 'Barangay 28, Sta. Cruz, Cavite City, Cavite', null, 100, 'available', 14.4713227, 120.8913757, 'DILG SubayBAYAN project 45003'],
    ['Dasmarinas City', 'Burol Main Evacuation Center', 'Burol Main, Dasmarinas City, Cavite', null, 0, 'available', 14.3273217, 120.9506564, 'DPWH evacuation center reference'],
    ['General Trias City', 'Bacao II Evacuation Center', 'Bacao II, General Trias City, Cavite', null, 0, 'available', 14.4090696, 120.8834133, 'General Trias evacuation center map reference'],
    ['Imus City', 'Malagasang 1-G Multi-Purpose Evacuation Center', 'Barangay Malagasang 1-G, Imus City, Cavite', null, 0, 'available', 14.3812633, 120.9163119, 'PIA completion notice'],
    ['Kawit', 'Binakayan-Congbalay-Legaspi Evacuation Facility', 'Barangay Binakayan-Congbalay-Legaspi, Kawit, Cavite', null, 28330, 'available', 14.4516315, 120.9240408, 'DILG SubayBAYAN project 20675'],
    ['Magallanes', 'Poblacion IV Evacuation Center', 'Poblacion IV, Magallanes, Cavite', null, 4998, 'available', 14.1872625, 120.7566091, 'DILG SubayBAYAN project 41868'],
    ['Magallanes', 'Magallanes Municipal Evacuation Facility', 'Barangay Poblacion IV, Magallanes, Cavite', null, 22727, 'available', 14.1872625, 120.7566091, 'DILG SubayBAYAN project 20679'],
    ['Maragondon', 'Bucal III-B Evacuation Center', 'Barangay Bucal III-B, Maragondon, Cavite', null, 40856, 'available', 14.2734682, 120.7553143, 'DILG SubayBAYAN project 42907'],
    ['Naic', 'Halang Evacuation Center', 'Barangay Halang, Naic, Cavite', null, 312, 'available', 14.2936712, 120.8022006, 'DILG SubayBAYAN project 37509'],
    ['Noveleta', 'San Juan II Evacuation Center', 'San Juan II, Noveleta, Cavite', null, 3852, 'available', 14.4374739, 120.8853659, 'DILG SubayBAYAN project 34625'],
    ['Noveleta', 'San Rafael Evacuation Center', 'San Rafael III, Noveleta, Cavite', null, 5986, 'available', 14.4348692, 120.8780837, 'DILG SubayBAYAN project 42207'],
    ['Noveleta', 'Jordan Estate San Jose II Evacuation Center', 'Jordan Estate Subdivision, San Jose II, Noveleta, Cavite', null, 2450, 'available', 14.4310969, 120.8860298, 'DILG SubayBAYAN project 37510'],
    ['Silang', 'Biga I Evacuation Center', 'Cavite State University Area, Barangay Biga I, Silang, Cavite', null, 4487, 'available', 14.2412562, 120.9791790, 'DILG SubayBAYAN project 41903'],
    ['Silang', 'Kaong Evacuation Center', 'Barangay Kaong, Silang, Cavite', null, 6710, 'available', 14.2445930, 120.9972455, 'DILG SubayBAYAN project 41901'],
    ['Tagaytay City', 'Sungay West Evacuation Center', 'Barangay Sungay West, Tagaytay City, Cavite', null, 1500, 'available', 14.1237630, 120.9918988, 'DILG SubayBAYAN project 49067'],
    ['Tanza', 'Amaya VII Evacuation Center', 'Barangay Amaya VII, Tanza, Cavite', null, 2451, 'available', 14.3885388, 120.8290180, 'DILG SubayBAYAN project 20696'],
    ['Ternate', 'Poblacion II Ternate Evacuation Center', 'Ternate Evacuation Center, Barangay Poblacion II, Ternate, Cavite', null, 23000, 'available', 14.2861913, 120.7185090, 'DILG SubayBAYAN project 43375'],
    ['Trece Martires City', 'Conchu Command Center Evacuation Center', 'Barangay Conchu, Trece Martires City, Cavite', null, 300, 'available', 14.2488633, 120.8865069, 'DILG SubayBAYAN project 48021'],
];

$municipalityIds = [];
$municipalityStatement = $db->query('SELECT id, municipality_name FROM municipalities WHERE status = "active"');
foreach ($municipalityStatement->fetchAll() as $row) {
    $municipalityIds[$row['municipality_name']] = (int) $row['id'];
}

$find = $db->prepare('SELECT id FROM evacuation_centers WHERE municipality_id = ? AND center_name = ? LIMIT 1');
$insert = $db->prepare(
    'INSERT INTO evacuation_centers (center_name,municipality_id,address,contact_number,capacity,status,latitude,longitude)
     VALUES (?,?,?,?,?,?,?,?)'
);
$update = $db->prepare(
    'UPDATE evacuation_centers
     SET address = ?, contact_number = ?, capacity = ?, status = ?, latitude = ?, longitude = ?
     WHERE id = ?'
);

$db->beginTransaction();
$seeded = 0;
foreach ($centers as [$municipality, $name, $address, $contact, $capacity, $status, $lat, $lng, $source]) {
    $municipalityId = $municipalityIds[$municipality] ?? null;
    if (!$municipalityId) {
        throw new RuntimeException("Municipality not found for evacuation center seed: {$municipality}");
    }
    $find->execute([$municipalityId, $name]);
    $existingId = $find->fetchColumn();
    if ($existingId) {
        $update->execute([$address, $contact, $capacity, $status, $lat, $lng, $existingId]);
    } else {
        $insert->execute([$name, $municipalityId, $address, $contact, $capacity, $status, $lat, $lng]);
    }
    $seeded++;
}
$db->commit();

echo "Seeded {$seeded} Cavite evacuation centers.\n";
