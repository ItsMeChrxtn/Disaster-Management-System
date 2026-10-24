<?php
// Imports the Cavite PDRRMO evacuation-center list and the 2021-2026 historical incident records
// (database/data/pdrrmo_*.txt). Idempotent: existing rows (same name/title, municipality, date) are skipped.
//   php database/seed_pdrrmo_revision3.php            -> seeds the configured database
//   php database/seed_pdrrmo_revision3.php --sql FILE  -> also writes a portable SQL file (municipality looked up by name)
require_once dirname(__DIR__) . '/bootstrap.php';

use App\Core\Database;
use App\Models\HistoricalDisaster;

$db = Database::connection();
new HistoricalDisaster(); // adds the revision-3 columns when missing
$sqlOut = null;
if (($i = array_search('--sql', $argv, true)) !== false) $sqlOut = $argv[$i + 1] ?? null;
$dry = in_array('--dry', $argv, true); // report only: everything is rolled back
if ($dry) $db->beginTransaction();

$municipalities = [];
foreach ($db->query('SELECT id,municipality_name,center_lat,center_lng FROM municipalities') as $m) $municipalities[$m['municipality_name']] = $m;

// ---- barangay centroids from the bundled PSA boundaries ----
function normBarangay(string $name): string
{
    $name = mb_strtolower(trim($name));
    $name = strtr($name, ['ñ' => 'n', 'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u']);
    $name = preg_replace('/\((pob\.?|poblacion)\)/', '', $name);
    $name = preg_replace('/\b(brgy\.?|barangay)\s+(?=[a-z])/', 'barangay ', $name);
    $name = preg_replace('/(\d)(st|nd|rd|th)\b/', '$1', $name);
    $name = preg_replace('/\bsta\.?\s/', 'santa ', $name);
    $name = preg_replace('/\bsto\.?\s/', 'santo ', $name);
    $name = preg_replace('/\bst\.\s/', 'saint ', $name);
    $roman = ['viii' => 8, 'vii' => 7, 'vi' => 6, 'iv' => 4, 'v' => 5, 'iii' => 3, 'ii' => 2, 'i' => 1, 'ix' => 9, 'xii' => 12, 'xi' => 11, 'x' => 10];
    $name = preg_replace_callback('/\b(xii|xi|ix|x|viii|vii|vi|iv|v|iii|ii|i)\b/', fn($m) => (string)$roman[$m[1]], $name);
    return preg_replace('/[^a-z0-9]/', '', $name);
}
$centroids = [];
$geo = json_decode(file_get_contents(dirname(__DIR__, 2) . '/frontend/assets/data/cavite-barangays.json'), true);
foreach ($geo['features'] as $f) {
    $rings = $f['geometry']['type'] === 'Polygon' ? [$f['geometry']['coordinates'][0]] : array_map(fn($p) => $p[0], $f['geometry']['coordinates']);
    $ring = array_reduce($rings, fn($best, $r) => count($r) > count($best ?? []) ? $r : $best);
    $a = 0; $cx = 0; $cy = 0;
    for ($k = 0, $n = count($ring) - 1; $k < $n; $k++) { [$x0, $y0] = $ring[$k]; [$x1, $y1] = $ring[$k + 1]; $c = $x0 * $y1 - $x1 * $y0; $a += $c; $cx += ($x0 + $x1) * $c; $cy += ($y0 + $y1) * $c; }
    if (abs($a) < 1e-12) { $cx = array_sum(array_column($ring, 0)) / count($ring); $cy = array_sum(array_column($ring, 1)) / count($ring); }
    else { $cx /= 3 * $a; $cy /= 3 * $a; }
    $centroids[$f['properties']['municipality']][normBarangay($f['properties']['name'])] = [round($cy, 7), round($cx, 7), $f['properties']['name']];
}
function barangayCentroid(array $centroids, string $municipality, string $barangay): ?array
{
    if ($barangay === '') return null;
    // Old barangay names in the LGU lists -> PSA 2023 names (Bacoor merged/renamed several barangays).
    $aliases = ['Bacoor City' => ['Alima' => 'Sinbanali', 'Banalo' => 'Sinbanali', 'Sineguelasan' => 'Sinbanali', 'Kaingin' => 'Kaingin Digman', 'Digman' => 'Kaingin Digman', 'Salinas III' => 'Salinas 2', 'Salinas IV' => 'Salinas 2', 'Talaba IV' => 'Talaba 3', 'Talaba V' => 'Talaba 3', 'Talaba VI' => 'Talaba 3', 'Talaba VII' => 'Talaba 3', 'Zapote IV' => 'Zapote 3', 'Zapote V' => 'Zapote 3', 'Mabolo I' => 'Mabolo', 'Mabolo II' => 'Mabolo', 'Mabolo III' => 'Mabolo', 'Niog I' => 'Niog', 'Niog II' => 'Niog', 'Niog III' => 'Niog', 'Real I' => 'Real', 'Real II' => 'Real'] + array_combine(array_map(fn($n) => 'Panapaan ' . $n, ['I', 'II', 'III', 'IV', 'V', 'VI']), array_map(fn($n) => 'P.F. Espiritu ' . $n, range(1, 6))), 'Kawit' => ['Potol' => 'Magdalo'], 'Trece Martires City' => ['Hugo Perez' => 'Perez'], 'Indang' => ['Poblacion I' => 'Barangay 1', 'Poblacion II' => 'Barangay 2', 'Poblacion III' => 'Barangay 3', 'Poblacion IV' => 'Barangay 4']];
    $barangay = $aliases[$municipality][$barangay] ?? $barangay;
    $list = $centroids[$municipality] ?? [];
    $key = normBarangay($barangay);
    if (isset($list[$key])) return $list[$key];
    foreach ($list as $k => $v) if (str_starts_with($k, $key) || str_starts_with($key, $k)) return $v;
    return null;
}

// ---- coordinates ----
function parseCoord(string $raw): ?float
{
    $raw = trim(str_replace(['°', '″', '′'], [' ', '"', "'"], $raw));
    if ($raw === '') return null;
    if (preg_match('/^-?\d+(\.\d+)?\s*$/', $raw)) return (float)$raw;
    if (preg_match('/^(\d+)\s+(\d+)\s*\'\s*([\d.]+)\s*"?\s*[NEne]?$/', $raw, $m)) return (int)$m[1] + (int)$m[2] / 60 + (float)$m[3] / 3600;
    return null;
}
function km(float $lat1, float $lng1, float $lat2, float $lng2): float
{
    return 6371 * acos(min(1, cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($lng2) - deg2rad($lng1)) + sin(deg2rad($lat1)) * sin(deg2rad($lat2))));
}

// ---- evacuation centers ----
$rows = [];
foreach (file(__DIR__ . '/data/pdrrmo_evacuation_centers.txt', FILE_IGNORE_NEW_LINES) as $line) {
    if ($line === '' || $line[0] === '#') continue;
    [$muni, $brgy, $name, $x, $y] = array_map('trim', explode('|', $line));
    $a = parseCoord($x); $b = parseCoord($y);
    $lat = $lng = null;
    if ($a !== null && $b !== null) { [$lat, $lng] = $a > 90 ? [$b, $a] : [$a, $b]; }
    $rows[] = compact('muni', 'brgy', 'name', 'lat', 'lng');
}
// A coordinate pair reused across 5+ barangays is a spreadsheet placeholder, not a location.
$pairBarangays = [];
foreach ($rows as $r) if ($r['lat'] !== null) $pairBarangays[$r['lat'] . ',' . $r['lng']][$r['brgy']] = true;

$centers = []; $report = ['exact' => 0, 'centroid' => 0, 'municipality' => 0, 'skipped' => []];
foreach ($rows as $r) {
    $m = $municipalities[$r['muni']] ?? null;
    if (!$m) { $report['skipped'][] = "unknown municipality {$r['muni']}"; continue; }
    $precision = 'exact'; $lat = $r['lat']; $lng = $r['lng'];
    $placeholder = $lat !== null && count($pairBarangays[$lat . ',' . $lng]) >= 5;
    $far = $lat !== null && km($lat, $lng, (float)$m['center_lat'], (float)$m['center_lng']) > 15;
    if ($lat === null || $placeholder || $far) {
        $c = barangayCentroid($centroids, $r['muni'], $r['brgy']);
        if ($c) { [$lat, $lng] = $c; $precision = 'centroid'; }
        else { $lat = (float)$m['center_lat']; $lng = (float)$m['center_lng']; $precision = 'municipality'; }
    }
    // Only rows sharing an exact source pin are the same building (e.g. one school serving several barangays).
    $key = $r['muni'] . '|' . mb_strtolower($r['name']) . '|' . ($precision === 'exact' ? round($lat, 5) . ',' . round($lng, 5) : $r['brgy']);
    if (!isset($centers[$key])) $centers[$key] = ['muni' => $r['muni'], 'mid' => (int)$m['id'], 'name' => $r['name'], 'barangays' => [], 'lat' => $lat, 'lng' => $lng, 'precision' => $precision];
    if ($r['brgy'] !== '') $centers[$key]['barangays'][] = $r['brgy'];
}

$sql = ["-- Cavite PDRRMO evacuation centers and historical records (revision 3, generated " . date('Y-m-d') . ")", "-- Safe to run more than once: every insert is skipped when the row already exists.", "SET NAMES utf8mb4;", '-- Revision-3 columns (the app also adds these by itself on first use; IF NOT EXISTS needs MariaDB).', 'ALTER TABLE historical_disasters ADD COLUMN IF NOT EXISTS event_name VARCHAR(160) NULL AFTER disaster_type, ADD COLUMN IF NOT EXISTS injured INT UNSIGNED NOT NULL DEFAULT 0 AFTER casualties, ADD COLUMN IF NOT EXISTS evacuated_families INT UNSIGNED NOT NULL DEFAULT 0 AFTER injured, ADD COLUMN IF NOT EXISTS affected_barangays TEXT NULL AFTER evacuated_families, ADD COLUMN IF NOT EXISTS affected_barangay_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER affected_barangays, ADD COLUMN IF NOT EXISTS source VARCHAR(255) NULL AFTER damages;'];
$q = fn($v) => $v === null ? 'NULL' : $db->quote((string)$v);
$exists = $db->prepare('SELECT 1 FROM evacuation_centers WHERE center_name=? AND municipality_id=? AND status<>"deleted"');
$insert = $db->prepare('INSERT INTO evacuation_centers (center_name,municipality_id,address,contact_person,contact_number,capacity,status,latitude,longitude) VALUES (?,?,?,NULL,NULL,0,?,?,?)');
$added = 0;
foreach ($centers as $c) {
    $barangays = array_values(array_unique($c['barangays']));
    $name = $c['name'];
    if (count($barangays) === 1 && stripos(normBarangay($name), normBarangay($barangays[0])) === false) $name .= ' (' . $barangays[0] . ')';
    $name = mb_substr($name, 0, 180);
    $address = ($barangays ? (count($barangays) === 1 ? 'Brgy. ' . $barangays[0] : 'Serves Brgy. ' . implode(', ', $barangays)) . ', ' : '') . $c['muni'] . ', Cavite';
    if ($c['precision'] === 'centroid') $address .= ' (map pin approximate: barangay center)';
    if ($c['precision'] === 'municipality') $address .= ' (map pin approximate: town center)';
    $address = mb_substr($address, 0, 255);
    $status = stripos($c['name'], 'not in use') !== false ? 'closed' : 'available';
    $report[$c['precision']]++;
    if ($dry && $c['precision'] === 'municipality') echo '  town-center pin: ' . $c['muni'] . ' / ' . implode(', ', $barangays) . ' / ' . $c['name'] . PHP_EOL;
    $exists->execute([$name, $c['mid']]);
    if (!$exists->fetchColumn()) { $insert->execute([$name, $c['mid'], $address, $status, $c['lat'], $c['lng']]); $added++; }
    $sql[] = sprintf('INSERT INTO evacuation_centers (center_name,municipality_id,address,contact_person,contact_number,capacity,status,latitude,longitude) SELECT %s,m.id,%s,NULL,NULL,0,%s,%s,%s FROM municipalities m WHERE m.municipality_name=%s AND NOT EXISTS (SELECT 1 FROM evacuation_centers e WHERE e.center_name=%s AND e.municipality_id=m.id AND e.status<>\'deleted\');',
        $q($name), $q($address), $q($status), $c['lat'], $c['lng'], $q($c['muni']), $q($name));
}
printf("Evacuation centers: %d facilities (%d exact pins, %d barangay-centroid, %d town-center), %d inserted.\n", count($centers), $report['exact'], $report['centroid'], $report['municipality'], $added);
foreach ($report['skipped'] as $s) echo "  skipped: $s\n";

// ---- historical disasters ----
$hExists = $db->prepare('SELECT 1 FROM historical_disasters WHERE title=? AND date_occurred=? AND ((? IS NULL AND municipality_id IS NULL) OR municipality_id=?)');
$hInsert = $db->prepare('INSERT INTO historical_disasters (title,disaster_type,event_name,description,municipality_id,date_occurred,casualties,injured,evacuated_families,affected_barangays,affected_barangay_count,damages,source) VALUES (?,?,?,?,?,?,?,?,?,?,?,0,?)');
$hAdded = 0; $hTotal = 0;
foreach (file(__DIR__ . '/data/pdrrmo_historical_disasters.txt', FILE_IGNORE_NEW_LINES) as $line) {
    if ($line === '' || $line[0] === '#') continue;
    [$date, $event, $type, $muni, $brgys, $dead, $injured, $families, $description, $source] = array_map('trim', explode('|', $line));
    $mid = $muni === '' ? null : (int)($municipalities[$muni]['id'] ?? 0);
    if ($mid === 0) { echo "  unknown municipality in history: $muni\n"; continue; }
    $list = array_values(array_filter(array_map('trim', explode(';', $brgys))));
    $title = mb_substr($muni === '' ? $event : $event . ' - ' . $type . ' in ' . $muni, 0, 180);
    $values = [$title, $type, $event, $description, $mid, $date, (int)$dead, (int)$injured, (int)$families, $list ? implode("\n", $list) : null, count($list), $source];
    $hTotal++;
    $hExists->execute([$title, $date, $mid, $mid]);
    if (!$hExists->fetchColumn()) { $hInsert->execute($values); $hAdded++; }
    $muniSql = $muni === '' ? 'NULL' : "(SELECT id FROM municipalities WHERE municipality_name=" . $q($muni) . " LIMIT 1)";
    $sql[] = sprintf('INSERT INTO historical_disasters (title,disaster_type,event_name,description,municipality_id,date_occurred,casualties,injured,evacuated_families,affected_barangays,affected_barangay_count,damages,source) SELECT %s,%s,%s,%s,%s,%s,%d,%d,%d,%s,%d,0,%s FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM historical_disasters h WHERE h.title=%s AND h.date_occurred=%s);',
        $q($title), $q($type), $q($event), $q($description), $muniSql, $q($date), (int)$dead, (int)$injured, (int)$families, $q($values[9]), count($list), $q($source), $q($title), $q($date));
}
printf("Historical records: %d in source, %d inserted.\n", $hTotal, $hAdded);

if ($dry) { $db->rollBack(); echo "Dry run: rolled back.
"; }
if ($sqlOut) { file_put_contents($sqlOut, implode("\n", $sql) . "\n"); echo "SQL written to $sqlOut\n"; }
