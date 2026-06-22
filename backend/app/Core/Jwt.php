<?php
namespace App\Core;

use RuntimeException;

final class Jwt
{
    public static function encode(array $claims): string
    {
        $header = ['alg' => 'HS256', 'typ' => 'JWT'];
        $segments = [self::base64Url(json_encode($header, JSON_THROW_ON_ERROR)), self::base64Url(json_encode($claims, JSON_THROW_ON_ERROR))];
        $segments[] = self::base64Url(hash_hmac('sha256', implode('.', $segments), self::secret(), true));
        return implode('.', $segments);
    }

    public static function decode(string $jwt): array
    {
        $parts = explode('.', $jwt);
        if (count($parts) !== 3) throw new RuntimeException('Malformed token');
        [$header, $payload, $signature] = $parts;
        $expected = self::base64Url(hash_hmac('sha256', "$header.$payload", self::secret(), true));
        if (!hash_equals($expected, $signature)) throw new RuntimeException('Invalid signature');
        $claims = json_decode(self::base64UrlDecode($payload), true, 16, JSON_THROW_ON_ERROR);
        if (($claims['iss'] ?? '') !== env('JWT_ISSUER', 'disaster-map-api')) throw new RuntimeException('Invalid issuer');
        if (!isset($claims['exp']) || (int) $claims['exp'] <= time()) throw new RuntimeException('Expired token');
        if (!isset($claims['sub'], $claims['jti'])) throw new RuntimeException('Incomplete token');
        return $claims;
    }

    private static function secret(): string
    {
        $secret = (string) env('JWT_SECRET', '');
        if (strlen($secret) < 32) throw new RuntimeException('JWT_SECRET must contain at least 32 characters');
        return $secret;
    }
    private static function base64Url(string $value): string { return rtrim(strtr(base64_encode($value), '+/', '-_'), '='); }
    private static function base64UrlDecode(string $value): string { return base64_decode(strtr($value, '-_', '+/')) ?: ''; }
}
