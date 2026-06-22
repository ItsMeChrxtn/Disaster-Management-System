<?php
namespace App\Middleware;

use App\Core\{Request, Response};

final class SecurityMiddleware
{
    public function __invoke(Request $request): void
    {
        $this->verifyOrigin($request);
        $this->rateLimit($request);
        $this->registerAudit($request);
    }

    private function verifyOrigin(Request $request): void
    {
        if (!in_array($request->method(), ['POST','PUT','PATCH','DELETE'], true)) return;
        $origin=$_SERVER['HTTP_ORIGIN']??'';
        if ($origin==='') return; // Non-browser clients authenticate with Bearer tokens.
        $originScheme=strtolower((string)parse_url($origin,PHP_URL_SCHEME));
        $originHost=strtolower((string)parse_url($origin,PHP_URL_HOST));
        $originPort=parse_url($origin,PHP_URL_PORT);
        $originAuthority=$originHost.($originPort!==null?':'.$originPort:'');
        $requestAuthority=strtolower((string)($_SERVER['HTTP_HOST']??''));
        // XAMPP and normal same-origin deployments may be opened through localhost,
        // 127.0.0.1, a LAN address, or a local hostname. Same-origin requests are
        // not CSRF and must not depend on a hard-coded FRONTEND_URL entry.
        if(in_array($originScheme,['http','https'],true)&&$originAuthority!==''&&hash_equals($requestAuthority,$originAuthority))return;
        if(env('APP_ENV','production')==='local'&&in_array($originHost,['localhost','127.0.0.1','::1'],true))return;
        $allowed=array_filter(array_map('trim',explode(',',(string)env('FRONTEND_URL',''))));
        if (!in_array($origin,$allowed,true)) Response::error('Request origin is not allowed',403);
    }

    private function rateLimit(Request $request): void
    {
        $isAuth=str_starts_with($request->path(),'/api/auth/login')||$request->path()==='/api/auth/forgot-password';
        $limit=$isAuth?10:180;$window=60;$bucket=(int)floor(time()/$window);
        $key=hash('sha256',($_SERVER['REMOTE_ADDR']??'unknown').'|'.$request->path().'|'.$bucket);
        $directory=sys_get_temp_dir().DIRECTORY_SEPARATOR.'disaster-map-rate-limits';
        if(!is_dir($directory)) @mkdir($directory,0700,true);
        $file=$directory.DIRECTORY_SEPARATOR.$key;
        $handle=@fopen($file,'c+');if(!$handle)return;
        try{flock($handle,LOCK_EX);$count=(int)stream_get_contents($handle);$count++;ftruncate($handle,0);rewind($handle);fwrite($handle,(string)$count);fflush($handle);}
        finally{flock($handle,LOCK_UN);fclose($handle);}
        header('X-RateLimit-Limit: '.$limit);header('X-RateLimit-Remaining: '.max(0,$limit-$count));
        if($count>$limit){header('Retry-After: '.($window-(time()%$window)));Response::error('Too many requests. Please try again shortly.',429);}
    }

    private function registerAudit(Request $request): void
    {
        $method=$request->method();$path=$request->path();
        if(!in_array($method,['POST','PUT','PATCH','DELETE'],true))return;
        register_shutdown_function(function()use($request,$method,$path):void{
            $status=http_response_code();if($status>=400)return;
            $action=match(true){str_contains($path,'/login')=>'login',str_contains($path,'/logout')=>'logout',str_contains($path,'/reports')=>'generate_report',$method==='POST'=>'create',$method==='PUT'||$method==='PATCH'=>'update',$method==='DELETE'=>'delete',default=>strtolower($method)};
            $parts=array_values(array_filter(explode('/',$path)));$module=$parts[1]??'system';$entityId=isset($parts[2])&&ctype_digit($parts[2])?(int)$parts[2]:null;
            try{$db=\App\Core\Database::connection();$stmt=$db->prepare('INSERT INTO audit_logs (user_id,action,entity_type,entity_id,metadata,ip_address) VALUES (?,?,?,?,?,?)');$stmt->execute([$request->user['id']??null,$action,$module,$entityId,json_encode(['method'=>$method,'path'=>$path,'status'=>$status],JSON_UNESCAPED_SLASHES),$_SERVER['REMOTE_ADDR']??null]);}catch(\Throwable){}
        });
    }
}
