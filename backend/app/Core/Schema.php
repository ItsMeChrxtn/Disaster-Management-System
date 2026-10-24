<?php
namespace App\Core;

// Additive, idempotent column migrations. Lets new optional columns roll out to
// an existing database (e.g. the live Hostinger copy) without a manual import.
final class Schema
{
    private static array $checked=[];

    public static function ensureColumn(string $table,string $column,string $definition): void
    {
        $key=$table.'.'.$column;
        if(isset(self::$checked[$key]))return;
        self::$checked[$key]=true;
        if(!preg_match('/^[a-z_]+$/',$table)||!preg_match('/^[a-z_]+$/',$column))return;
        $db=Database::connection();
        try{
            if($db->query("SHOW COLUMNS FROM `$table` LIKE '$column'")->fetch())return;
            $db->exec("ALTER TABLE `$table` ADD COLUMN `$column` $definition");
        }catch(\Throwable){
            // Missing ALTER privilege: queries fall back to the columns that exist.
        }
    }

    /** Runs a CREATE TABLE IF NOT EXISTS once per request, for tables added after the initial import. */
    public static function ensureTable(string $table,string $createSql): void
    {
        if(isset(self::$checked[$table]))return;
        self::$checked[$table]=true;
        try{Database::connection()->exec($createSql);}catch(\Throwable){
            // Missing CREATE privilege: the matching migrate_*.sql file must be imported manually.
        }
    }

    public static function hasColumn(string $table,string $column): bool
    {
        if(!preg_match('/^[a-z_]+$/',$table)||!preg_match('/^[a-z_]+$/',$column))return false;
        try{return (bool)Database::connection()->query("SHOW COLUMNS FROM `$table` LIKE '$column'")->fetch();}catch(\Throwable){return false;}
    }
}
