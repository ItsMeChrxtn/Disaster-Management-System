<?php
namespace App\Middleware;

use App\Core\{Database, Jwt, Request, Response};

final class AuthMiddleware
{
    public function __invoke(Request $request): void {
        $token=$request->bearerToken(); if(!$token) Response::error('Authentication required',401);
        try{$claims=Jwt::decode($token);}catch(\Throwable){Response::error('Invalid or expired token',401);}
        $sql='SELECT u.id,u.fullname,u.email,u.phone,u.address,u.barangay,u.role,u.municipality_id,u.status,m.municipality_name
              FROM user_sessions s JOIN users u ON u.id=s.user_id LEFT JOIN municipalities m ON m.id=u.municipality_id
              WHERE s.jti=? AND s.user_id=? AND s.revoked_at IS NULL AND s.expires_at>UTC_TIMESTAMP() AND u.status="active"';
        $stmt=Database::connection()->prepare($sql);$stmt->execute([$claims['jti'],(int)$claims['sub']]);$request->user=$stmt->fetch()?:null;
        if(!$request->user) Response::error('Session is no longer valid',401);
        $request->params['_jwt_jti']=$claims['jti'];
    }
}
