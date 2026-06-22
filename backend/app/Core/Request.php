<?php
namespace App\Core;

final class Request
{
    public array $params = [];
    public ?array $user = null;
    private ?array $json = null;

    public function method(): string { return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET'); }
    public function path(): string {
        $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
        // Support both a dedicated API domain (/api/...) and an Apache
        // subdirectory deployment (.../backend/public/api/...).
        $apiPosition = strpos($path, '/api');
        if ($apiPosition !== false) $path = substr($path, $apiPosition);
        return '/' . trim($path, '/');
    }
    public function body(): array {
        if ($this->json !== null) return $this->json;
        $decoded = json_decode(file_get_contents('php://input') ?: '{}', true);
        return $this->json = is_array($decoded) ? $decoded : [];
    }
    public function query(string $key, mixed $default = null): mixed { return $_GET[$key] ?? $default; }
    public function bearerToken(): ?string {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        return preg_match('/^Bearer\s+(\S+)$/i', $header, $m) ? $m[1] : null;
    }
}
