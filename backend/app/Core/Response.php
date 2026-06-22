<?php
namespace App\Core;

final class Response
{
    public static function json(mixed $data, int $status = 200): never {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        exit;
    }
    public static function success(mixed $data = null, int $status = 200): never {
        self::json(['success' => true, 'data' => $data], $status);
    }
    public static function error(string $message, int $status = 400, array $errors = []): never {
        self::json(['success' => false, 'message' => $message, 'errors' => $errors], $status);
    }
}

