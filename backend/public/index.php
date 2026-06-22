<?php
declare(strict_types=1);
require dirname(__DIR__) . '/bootstrap.php';

use App\Core\{Request, Response};

$origin=$_SERVER['HTTP_ORIGIN']??''; $allowed=array_filter(array_map('trim',explode(',',(string)env('FRONTEND_URL',''))));
$originHost=strtolower((string)parse_url($origin,PHP_URL_HOST));
$localDevelopmentOrigin=env('APP_ENV','production')==='local'&&in_array($originHost,['localhost','127.0.0.1','::1'],true);
if(in_array($origin,$allowed,true)||$localDevelopmentOrigin){ header('Access-Control-Allow-Origin: '.$origin); header('Vary: Origin'); }
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-CSRF-Token');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('X-Content-Type-Options: nosniff'); header('X-Frame-Options: DENY'); header('Referrer-Policy: strict-origin-when-cross-origin');
header("Permissions-Policy: geolocation=(self), camera=(), microphone=()");
header("Content-Security-Policy: default-src 'none'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
if(($_SERVER['REQUEST_METHOD']??'GET')==='OPTIONS'){http_response_code(204);exit;}
try { $router=require dirname(__DIR__).'/routes/api.php'; $router->dispatch(new Request()); }
catch(Throwable $e){ if(env('APP_DEBUG',false)) Response::error($e->getMessage(),500,['trace'=>$e->getTraceAsString()]); Response::error('Internal server error',500); }
