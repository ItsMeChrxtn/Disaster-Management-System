<?php
namespace App\Middleware;

use App\Core\{Request, Response};

final class RoleMiddleware
{
    public static function allow(string ...$roles): callable {
        return function (Request $request) use ($roles): void {
            if (!$request->user || !in_array($request->user['role'], $roles, true)) Response::error('Forbidden', 403);
        };
    }
}

