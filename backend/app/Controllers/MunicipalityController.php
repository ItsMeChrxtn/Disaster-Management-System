<?php
namespace App\Controllers;

use App\Core\{Request, Response, Validator};
use App\Models\Municipality;

final class MunicipalityController
{
    public function index(Request $r): never { Response::success((new Municipality())->all()); }
    public function options(Request $r): never { Response::success((new Municipality())->all(false)); }
    public function show(Request $r): never
    {
        $item=(new Municipality())->find((int)$r->params['id']);if(!$item)Response::error('Municipality not found',404);Response::success($item);
    }
    public function store(Request $r): never
    {
        $data=$this->validated($r);$model=new Municipality();if($model->nameExists($data['municipality_name']))Response::error('Municipality name already exists',409,['municipality_name'=>'Must be unique']);$id=$model->create($data);Response::success($model->find($id),201);
    }
    public function update(Request $r): never
    {
        $id=(int)$r->params['id'];$model=new Municipality();if(!$model->find($id))Response::error('Municipality not found',404);$data=$this->validated($r);if($model->nameExists($data['municipality_name'],$id))Response::error('Municipality name already exists',409,['municipality_name'=>'Must be unique']);$model->update($id,$data);Response::success($model->find($id));
    }
    public function destroy(Request $r): never
    {
        $id=(int)$r->params['id'];$model=new Municipality();if(!$model->find($id))Response::error('Municipality not found',404);
        try{$model->delete($id);}
        catch(\PDOException $e){if($e->getCode()==='23000')Response::error('Cannot delete municipality because related records still reference it',409);throw $e;}
        Response::success(['message'=>'Municipality deleted']);
    }
    private function validated(Request $r): array
    {
        $d=$r->body();Validator::require($d,['municipality_name','status']);$name=trim((string)$d['municipality_name']);$description=trim((string)($d['description']??''));
        $errors=[];if(strlen($name)<2||strlen($name)>120)$errors['municipality_name']='Must contain 2 to 120 characters';if(strlen($description)>2000)$errors['description']='Must not exceed 2000 characters';if(!in_array($d['status'],['active','inactive'],true))$errors['status']='Must be active or inactive';if($errors)Response::error('Validation failed',422,$errors);
        return ['municipality_name'=>$name,'description'=>$description?:null,'status'=>$d['status']];
    }
}
