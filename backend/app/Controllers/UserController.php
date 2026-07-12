<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\User;

final class UserController
{
    public function index(Request $r): never { $mid=$r->user['role']==='subadmin'?(int)$r->user['municipality_id']:null;Response::success((new User())->managedList($mid)); }
    public function show(Request $r): never { Response::success($this->scopedUser($r)); }
    public function store(Request $r): never
    {
        $data=$this->validated($r,true);$plainPassword=$data['password'];$data['password_must_change']=true;$model=new User();$id=$model->managementCreate($data);$item=$model->findManaged($id);
        Response::success(['user'=>$item,'temporary_password'=>$plainPassword,'message'=>'User created. Sending temporary password by EmailJS...'],201);
    }
    public function update(Request $r): never
    {
        $id=(int)$r->params['id'];$model=new User();if(!$model->findManaged($id))Response::error('User not found',404);$data=$this->validated($r,false,$id);if($id===(int)$r->user['id']&&$data['role']!=='admin')Response::error('You cannot remove your own Admin role',422);$model->managementUpdate($id,$data);if($data['password']!=='')$model->revokeSessions($id);Response::success($model->findManaged($id));
    }
    public function destroy(Request $r): never { $this->changeStatus($r,'deleted','User deleted'); }
    public function disable(Request $r): never { $this->changeStatus($r,'disabled','User disabled'); }
    public function activate(Request $r): never { $this->changeStatus($r,'active','User activated',false); }

    private function changeStatus(Request $r,string $status,string $message,bool $revoke=true): never
    {
        $id=(int)$r->params['id'];if($id===(int)$r->user['id'])Response::error('You cannot change your own account status',422);$model=new User();$item=$model->findManaged($id);if(!$item)Response::error('User not found',404);if($status==='active'&&$item['status']==='deleted')Response::error('Deleted users cannot be activated',422);$model->setStatus($id,$status);if($revoke)$model->revokeSessions($id);Response::success(['message'=>$message,'user'=>$model->findManaged($id)]);
    }
    private function scopedUser(Request $r): array
    {
        $item=(new User())->findManaged((int)$r->params['id']);if(!$item)Response::error('User not found',404);if($r->user['role']==='subadmin'&&($item['role']!=='resident'||(int)$item['municipality_id']!==(int)$r->user['municipality_id']||$item['status']==='deleted'))Response::error('Forbidden',403);return $item;
    }
    private function validated(Request $r,bool $creating,?int $id=null): array
    {
        $d=$r->body();$required=['fullname','email','role'];Validator::require($d,$required);$errors=[];$name=trim((string)$d['fullname']);$email=strtolower(trim((string)$d['email']));$role=(string)$d['role'];$password=trim((string)($d['password']??''));if($creating&&$password==='')$password=$this->temporaryPassword();$mid=isset($d['municipality_id'])&&$d['municipality_id']!==''?(int)$d['municipality_id']:null;
        if(strlen($name)<2||strlen($name)>150)$errors['fullname']='Must contain 2 to 150 characters';if(!filter_var($email,FILTER_VALIDATE_EMAIL))$errors['email']='Invalid email address';if(!in_array($role,['admin','subadmin','resident'],true))$errors['role']='Invalid role';if(($creating||$password!=='')&&strlen($password)<8)$errors['password']='Must contain at least 8 characters';if($role!=='admin'&&!$mid)$errors['municipality_id']='Required for Sub Admin and Resident roles';
        $db=Database::connection();$s=$db->prepare('SELECT 1 FROM users WHERE email=? AND id<>?');$s->execute([$email,$id??0]);if($s->fetchColumn())$errors['email']='Email is already in use';if($mid){$s=$db->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$s->execute([$mid]);if(!$s->fetchColumn())$errors['municipality_id']='Municipality is invalid or inactive';}if($errors)Response::error('Validation failed',422,$errors);
        return ['municipality_id'=>$mid,'fullname'=>$name,'email'=>$email,'password'=>$password,'phone'=>trim((string)($d['phone']??''))?:null,'address'=>trim((string)($d['address']??''))?:null,'barangay'=>trim((string)($d['barangay']??''))?:null,'role'=>$role];
    }
    private function temporaryPassword(): string
    {
        return 'DM-'.bin2hex(random_bytes(4)).'-'.random_int(100,999);
    }
}
