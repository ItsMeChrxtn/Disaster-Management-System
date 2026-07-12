<?php
namespace App\Core;

use PDO;

final class Database
{
    private static ?PDO $connection = null;

    public static function connection(): PDO
    {
        if (self::$connection) return self::$connection;
        [$dsn,$username,$password]=self::config();
        self::$connection = new PDO($dsn, $username, $password, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        return self::$connection;
    }

    private static function config(): array
    {
        $url=(string)(env('DATABASE_URL','')?:env('MYSQL_URL',''));
        if($url!==''){
            $parts=parse_url($url);
            if($parts&&isset($parts['host'])){
                $database=ltrim((string)($parts['path']??''),'/');
                $query=[];
                if(isset($parts['query']))parse_str($parts['query'],$query);
                $dsn=sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',$parts['host'],$parts['port']??3306,$database?:($query['database']??''));
                return [$dsn,urldecode((string)($parts['user']??'')),urldecode((string)($parts['pass']??''))];
            }
        }
        $host=(string)(env('MYSQLHOST','')?:env('DB_HOST','127.0.0.1'));
        $port=(string)(env('MYSQLPORT','')?:env('DB_PORT','3306'));
        $database=(string)(env('MYSQLDATABASE','')?:env('DB_DATABASE',''));
        $username=(string)(env('MYSQLUSER','')?:env('DB_USERNAME','root'));
        $password=(string)(env('MYSQLPASSWORD','')?:env('DB_PASSWORD',''));
        return [sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4',$host,$port,$database),$username,$password];
    }
}
