<?php
namespace App\Services;

final class UserCredentialMailer
{
    public function sendCreatedPassword(string $to,string $name,string $password,string $role): bool
    {
        $subject='Your Disaster Map account password';
        $loginUrl=(string)env('FRONTEND_APP_URL','');
        if($loginUrl===''){
            $origin=rtrim((string)env('FRONTEND_URL','http://localhost'),', ');
            if(str_contains($origin,','))$origin=trim(explode(',',$origin)[0]);
            $loginUrl=rtrim($origin,'/').'/Disaster-Management-System/frontend';
        }
        $loginUrl=rtrim($loginUrl,'/').'/login.html';
        $body="Hello {$name},\n\nYour Disaster Map account has been created.\n\nRole: {$role}\nEmail: {$to}\nTemporary password: {$password}\n\nSign in here: {$loginUrl}\n\nFor security, change your password immediately after signing in from Profile & password.\n\nDisaster Map Operations";
        $from=(string)env('MAIL_FROM','no-reply@disastermap.local');
        $headers=[
            'From: Disaster Map <'.$from.'>',
            'Reply-To: '.$from,
            'Content-Type: text/plain; charset=UTF-8',
            'X-Mailer: PHP/'.PHP_VERSION
        ];
        $sent=false;
        try{$sent=mail($to,$subject,$body,implode("\r\n",$headers));}catch(\Throwable){$sent=false;}
        if(!$sent||env('APP_DEBUG',false))$this->writeLocalCopy($to,$subject,$body,$sent);
        return $sent;
    }

    private function writeLocalCopy(string $to,string $subject,string $body,bool $sent): void
    {
        $directory=BASE_PATH.'/storage/mail';
        if(!is_dir($directory)&&!mkdir($directory,0775,true)&&!is_dir($directory))return;
        $filename=$directory.'/user_password_'.gmdate('Ymd_His').'_'.bin2hex(random_bytes(3)).'.txt';
        file_put_contents($filename,"Sent: ".($sent?'yes':'no')."\nTo: {$to}\nSubject: {$subject}\n\n{$body}\n");
    }
}
