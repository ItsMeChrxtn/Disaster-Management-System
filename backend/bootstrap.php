<?php
declare(strict_types=1);

define('BASE_PATH', __DIR__);

if (is_file(BASE_PATH . '/vendor/autoload.php')) require BASE_PATH . '/vendor/autoload.php';

$composerAutoload=BASE_PATH.'/vendor/autoload.php';
if(is_file($composerAutoload))require_once $composerAutoload;

spl_autoload_register(function (string $class): void {
    $prefix = 'App\\';
    if (!str_starts_with($class, $prefix)) return;
    $file = BASE_PATH . '/app/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    if (is_file($file)) require $file;
});

$appFileEnv = [];
$envFile = BASE_PATH . '/.env';
if (is_file($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#') || !str_contains($line, '=')) continue;
        [$key, $value] = array_map('trim', explode('=', $line, 2));
        $appFileEnv[$key] = trim($value, "\"'");
    }
}

function env(string $key, mixed $default = null): mixed {
    global $appFileEnv;
    // Never call putenv() here. XAMPP uses a threaded Apache MPM, so mutating
    // process-wide environment state per request causes intermittent JWT and
    // database failures when requests run concurrently.
    $systemValue = getenv($key);
    $value = $systemValue !== false ? $systemValue : ($appFileEnv[$key] ?? null);
    if ($value === null) return $default;
    return match (strtolower($value)) {'true' => true, 'false' => false, 'null' => null, default => $value};
}

date_default_timezone_set('UTC');
