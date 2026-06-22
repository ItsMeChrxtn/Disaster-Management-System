<?php
namespace App\Core;

final class Validator
{
    public static function require(array $data, array $fields): void {
        $errors = [];
        foreach ($fields as $field) {
            $missing=!array_key_exists($field,$data)||$data[$field]===null;
            $emptyString=is_string($data[$field]??null)&&trim($data[$field])==='';
            $emptyArray=is_array($data[$field]??null)&&$data[$field]===[];
            if($missing||$emptyString||$emptyArray)$errors[$field]='Required';
        }
        if ($errors) Response::error('Validation failed', 422, $errors);
    }
}
