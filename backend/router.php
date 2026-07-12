<?php
declare(strict_types=1);

// Router for PHP's built-in server. Existing files are served directly;
// every application request is handled by the API front controller.
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$publicFile = __DIR__ . '/public' . $path;

if ($path !== '/' && is_file($publicFile)) {
    return false;
}

require __DIR__ . '/public/index.php';
