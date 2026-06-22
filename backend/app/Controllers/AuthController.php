<?php
namespace App\Controllers;

use App\Core\{Database, Jwt, Request, Response, Validator};
use App\Models\User;

final class AuthController
{
    public function register(Request $r): never
    {
        $d=$r->body();Validator::require($d,['fullname','email','password','phone','address','municipality_id','barangay']);
        $this->validateEmailPassword($d);$users=new User();
        if($users->findByEmail($d['email']))Response::error('Email is already registered',409);
        $id=$users->create($d);Response::success($users->publicById($id),201);
    }

    public function login(Request $r): never { $this->authenticate($r,null); }
    public function adminLogin(Request $r): never { $this->authenticate($r,'admin'); }
    public function subadminLogin(Request $r): never { $this->authenticate($r,'subadmin'); }
    public function residentLogin(Request $r): never { $this->authenticate($r,'resident'); }

    private function authenticate(Request $r,?string $requiredRole): never
    {
        $d=$r->body();Validator::require($d,['email','password']);$user=(new User())->findByEmail(strtolower($d['email']));
        if(!$user||!password_verify($d['password'],$user['password'])||$user['status']!=='active'||($requiredRole&&$user['role']!==$requiredRole))Response::error('Invalid credentials',401);
        if(password_needs_rehash($user['password'],PASSWORD_DEFAULT)){Database::connection()->prepare('UPDATE users SET password=? WHERE id=?')->execute([password_hash($d['password'],PASSWORD_DEFAULT),$user['id']]);}
        $hours=max(1,(int)env('TOKEN_TTL_HOURS',24));$now=time();$jti=bin2hex(random_bytes(16));$expires=$now+$hours*3600;
        $token=Jwt::encode(['iss'=>env('JWT_ISSUER','disaster-map-api'),'sub'=>(string)$user['id'],'jti'=>$jti,'role'=>$user['role'],'iat'=>$now,'exp'=>$expires]);
        Database::connection()->prepare('INSERT INTO user_sessions (jti,user_id,expires_at,user_agent,ip_address) VALUES (?,?,FROM_UNIXTIME(?),?,?)')->execute([$jti,$user['id'],$expires,substr($_SERVER['HTTP_USER_AGENT']??'',0,255),$_SERVER['REMOTE_ADDR']??null]);
        unset($user['password']);Response::success(['access_token'=>$token,'token_type'=>'Bearer','expires_in'=>$hours*3600,'user'=>$user]);
    }

    public function me(Request $r): never { Response::success($r->user); }
    public function logout(Request $r): never { Database::connection()->prepare('UPDATE user_sessions SET revoked_at=UTC_TIMESTAMP() WHERE jti=?')->execute([$r->params['_jwt_jti']]);Response::success(['message'=>'Logged out']); }

    public function forgotPassword(Request $r): never
    {
        $d=$r->body();Validator::require($d,['email']);$user=(new User())->findByEmail(strtolower($d['email']));$debugToken=null;
        if($user&&$user['status']==='active'){$raw=bin2hex(random_bytes(32));$minutes=max(5,(int)env('PASSWORD_RESET_TTL_MINUTES',30));Database::connection()->prepare('UPDATE password_reset_tokens SET used_at=UTC_TIMESTAMP() WHERE user_id=? AND used_at IS NULL')->execute([$user['id']]);Database::connection()->prepare('INSERT INTO password_reset_tokens (user_id,token_hash,expires_at) VALUES (?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? MINUTE))')->execute([$user['id'],hash('sha256',$raw),$minutes]);if(env('APP_DEBUG',false))$debugToken=$raw;/* Send $raw using a configured mail provider in production. */}
        $response=['message'=>'If the account exists, password reset instructions have been generated.'];if($debugToken)$response['debug_reset_token']=$debugToken;Response::success($response);
    }

    public function resetPassword(Request $r): never
    {
        $d=$r->body();Validator::require($d,['token','password','password_confirmation']);$this->validatePasswordConfirmation($d);
        $db=Database::connection();$s=$db->prepare('SELECT * FROM password_reset_tokens WHERE token_hash=? AND used_at IS NULL AND expires_at>UTC_TIMESTAMP() LIMIT 1');$s->execute([hash('sha256',$d['token'])]);$reset=$s->fetch();if(!$reset)Response::error('Reset token is invalid or expired',422);
        $db->beginTransaction();try{$db->prepare('UPDATE users SET password=? WHERE id=?')->execute([password_hash($d['password'],PASSWORD_DEFAULT),$reset['user_id']]);$db->prepare('UPDATE password_reset_tokens SET used_at=UTC_TIMESTAMP() WHERE id=?')->execute([$reset['id']]);$db->prepare('UPDATE user_sessions SET revoked_at=UTC_TIMESTAMP() WHERE user_id=? AND revoked_at IS NULL')->execute([$reset['user_id']]);$db->commit();}catch(\Throwable $e){$db->rollBack();throw $e;}Response::success(['message'=>'Password reset successfully']);
    }

    public function changePassword(Request $r): never
    {
        $d=$r->body();Validator::require($d,['current_password','password','password_confirmation']);$this->validatePasswordConfirmation($d);$user=(new User())->findByEmail($r->user['email']);if(!$user||!password_verify($d['current_password'],$user['password']))Response::error('Current password is incorrect',422);
        $db=Database::connection();$db->prepare('UPDATE users SET password=? WHERE id=?')->execute([password_hash($d['password'],PASSWORD_DEFAULT),$r->user['id']]);$db->prepare('UPDATE user_sessions SET revoked_at=UTC_TIMESTAMP() WHERE user_id=? AND jti<>? AND revoked_at IS NULL')->execute([$r->user['id'],$r->params['_jwt_jti']]);Response::success(['message'=>'Password changed successfully']);
    }

    public function updateProfile(Request $r): never
    {
        $d=$r->body();Validator::require($d,['fullname','email']);if(!filter_var($d['email'],FILTER_VALIDATE_EMAIL))Response::error('Invalid email address',422);
        $db=Database::connection();$s=$db->prepare('SELECT 1 FROM users WHERE email=? AND id<>?');$s->execute([strtolower($d['email']),$r->user['id']]);if($s->fetchColumn())Response::error('Email is already in use',409);
        $db->prepare('UPDATE users SET fullname=?,email=?,phone=?,address=?,municipality_id=?,barangay=? WHERE id=?')->execute([$d['fullname'],strtolower($d['email']),$d['phone']??null,$d['address']??null,$d['municipality_id']?:null,$d['barangay']??null,$r->user['id']]);Response::success((new User())->publicById((int)$r->user['id']));
    }

    private function validateEmailPassword(array $d): void { if(!filter_var($d['email'],FILTER_VALIDATE_EMAIL))Response::error('Invalid email address',422);if(strlen($d['password'])<8)Response::error('Password must be at least 8 characters',422); }
    private function validatePasswordConfirmation(array $d): void { if(strlen($d['password'])<8)Response::error('Password must be at least 8 characters',422);if($d['password']!==$d['password_confirmation'])Response::error('Password confirmation does not match',422); }
}
