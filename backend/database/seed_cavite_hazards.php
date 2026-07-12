<?php
require_once dirname(__DIR__) . '/bootstrap.php';

use App\Core\Database;

$db = Database::connection();

$adminId = (int) ($db->query("SELECT id FROM users WHERE role = 'admin' ORDER BY id LIMIT 1")->fetchColumn() ?: 1);
$municipalityIds = [];
foreach ($db->query('SELECT id, municipality_name FROM municipalities')->fetchAll() as $row) {
    $municipalityIds[$row['municipality_name']] = (int) $row['id'];
}

function box(float $lat, float $lng, float $dLat, float $dLng): string
{
    $west = $lng - $dLng;
    $east = $lng + $dLng;
    $south = $lat - $dLat;
    $north = $lat + $dLat;
    return json_encode([
        'type' => 'Polygon',
        'coordinates' => [[
            [$west, $south],
            [$east, $south],
            [$east, $north],
            [$west, $north],
            [$west, $south],
        ]],
    ], JSON_UNESCAPED_SLASHES);
}

function line(array $points): string
{
    return json_encode(['type' => 'LineString', 'coordinates' => $points], JSON_UNESCAPED_SLASHES);
}

$sourceFlood = 'Source-backed representative hazard based on JICA lowland Cavite flood mitigation coverage for Bacoor, Imus, Kawit, Noveleta, Rosario, General Trias, and Tanza. Geometry is an operational planning approximation, not an official cadastral boundary.';
$sourceStorm = 'Source-backed representative hazard based on Cavite coastal exposure and storm-surge planning references. Geometry is an operational planning approximation, not an official storm-surge inundation shapefile.';
$sourceQuake = 'Source-backed representative hazard based on PHIVOLCS Valley Fault System references. Line geometry is an operational planning trace approximation, not a survey-grade fault trace.';

$hazards = [
    ['Bacoor Lowland Floodplain', 'flood_zone', 'Bacoor City', 'high', $sourceFlood, box(14.4590, 120.9490, 0.030, 0.026)],
    ['Imus River Floodplain', 'flood_zone', 'Imus City', 'high', $sourceFlood, box(14.4297, 120.9367, 0.026, 0.024)],
    ['Kawit Lowland Flood Area', 'flood_zone', 'Kawit', 'high', $sourceFlood, box(14.4443, 120.9015, 0.018, 0.018)],
    ['Noveleta Lowland Flood Area', 'flood_zone', 'Noveleta', 'high', $sourceFlood, box(14.4292, 120.8799, 0.016, 0.016)],
    ['Rosario Lowland Flood Area', 'flood_zone', 'Rosario', 'high', $sourceFlood, box(14.4140, 120.8570, 0.017, 0.018)],
    ['Tanza-Canas River Flood Corridor', 'flood_zone', 'Tanza', 'moderate', $sourceFlood, box(14.3940, 120.8530, 0.028, 0.025)],
    ['General Trias Lowland Flood Corridor', 'flood_zone', 'General Trias City', 'moderate', $sourceFlood, box(14.3869, 120.8816, 0.026, 0.025)],

    ['Cavite City Coastal Storm Surge Area', 'storm_surge_area', 'Cavite City', 'critical', $sourceStorm, box(14.4837, 120.8988, 0.018, 0.023)],
    ['Bacoor Coastal Storm Surge Area', 'storm_surge_area', 'Bacoor City', 'high', $sourceStorm, box(14.4590, 120.9290, 0.020, 0.027)],
    ['Kawit-Noveleta-Rosario Coastal Storm Surge Belt', 'storm_surge_area', 'Noveleta', 'critical', $sourceStorm, box(14.4280, 120.8830, 0.030, 0.045)],
    ['Tanza-Naic Coastal Storm Surge Belt', 'storm_surge_area', 'Tanza', 'high', $sourceStorm, box(14.3600, 120.8100, 0.050, 0.055)],
    ['Maragondon-Ternate Coastal Storm Surge Belt', 'storm_surge_area', 'Ternate', 'moderate', $sourceStorm, box(14.2790, 120.7200, 0.042, 0.040)],

    ['West Valley Fault Planning Trace - Carmona', 'earthquake_area', 'Carmona City', 'critical', $sourceQuake, line([[121.0300, 14.3500], [121.0480, 14.3300], [121.0620, 14.3060]])],
    ['West Valley Fault Planning Trace - General Mariano Alvarez', 'earthquake_area', 'General Mariano Alvarez', 'critical', $sourceQuake, line([[121.0000, 14.3250], [121.0120, 14.3030], [121.0220, 14.2870]])],
    ['West Valley Fault Planning Trace - Silang', 'earthquake_area', 'Silang', 'high', $sourceQuake, line([[120.9850, 14.2650], [120.9970, 14.2350], [121.0100, 14.2050]])],
];

$select = $db->prepare('SELECT id FROM hazards WHERE hazard_name = ?');
$insert = $db->prepare(
    'INSERT INTO hazards (hazard_name,hazard_type,municipality_id,risk_level,description,geojson_data,created_by,status)
     VALUES (?,?,?,?,?,?,?,"active")'
);
$update = $db->prepare(
    'UPDATE hazards
     SET hazard_type = ?, municipality_id = ?, risk_level = ?, description = ?, geojson_data = ?, created_by = ?, status = "active"
     WHERE id = ?'
);

$db->beginTransaction();
$db->exec(
    "UPDATE hazards
     SET status = 'archived'
     WHERE LOWER(hazard_name) LIKE 'test%'
        OR hazard_name IN (
            'Bacoor Flood Zone',
            'Bacoor Coastal Storm Surge Area Demo',
            'Imus Earthquake Planning Area',
            'Dasmarinas High-Risk Area'
        )"
);
foreach ($hazards as [$name, $type, $municipality, $risk, $description, $geojson]) {
    if (!isset($municipalityIds[$municipality])) {
        throw new RuntimeException("Missing municipality: $municipality");
    }
    $select->execute([$name]);
    $existingId = $select->fetchColumn();
    if ($existingId) {
        $update->execute([$type, $municipalityIds[$municipality], $risk, $description, $geojson, $adminId, $existingId]);
    } else {
        $insert->execute([$name, $type, $municipalityIds[$municipality], $risk, $description, $geojson, $adminId]);
    }
}
$db->commit();

echo 'Seeded ' . count($hazards) . " Cavite hazard records.\n";
