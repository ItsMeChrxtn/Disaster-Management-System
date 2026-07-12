<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response, Validator};
use App\Models\Report;
use App\Services\ReportGenerator;

final class ReportController
{
    private const TYPES=['hazard','alert','historical_disaster','evacuation_center'];
    public function index(Request $request): never
    {
        Response::success((new Report())->all($request->user['role']==='subadmin'?(int)$request->user['id']:null));
    }
    public function store(Request $request): never
    {
        $data=$request->body();Validator::require($data,['report_type','format']);$errors=[];
        if(!in_array($data['report_type'],self::TYPES,true))$errors['report_type']='Select a supported report type';
        if(!in_array($data['format'],['pdf','xlsx'],true))$errors['format']='Format must be PDF or Excel';
        foreach(['date_from','date_to'] as $field)if(!empty($data[$field])&&!$this->date($data[$field]))$errors[$field]='Use YYYY-MM-DD';
        if(!empty($data['date_from'])&&!empty($data['date_to'])&&$data['date_from']>$data['date_to'])$errors['date_to']='Must be on or after the start date';
        if($errors)Response::error('Validation failed',422,$errors);
        $municipalityId=$request->user['role']==='subadmin'?(int)$request->user['municipality_id']:(isset($data['municipality_id'])&&$data['municipality_id']!==''?(int)$data['municipality_id']:null);
        if($municipalityId){$statement=Database::connection()->prepare('SELECT 1 FROM municipalities WHERE id=? AND status="active"');$statement->execute([$municipalityId]);if(!$statement->fetchColumn())Response::error('Validation failed',422,['municipality_id'=>'Municipality is invalid or inactive']);}
        $path=(new ReportGenerator())->generate($data['report_type'],$data['format'],$municipalityId,$data['date_from']??null,$data['date_to']??null,$request->user['fullname']);
        $model=new Report();$id=$model->create($data['report_type'],(int)$request->user['id'],$path);Response::success($model->find($id),201);
    }
    public function download(Request $request): never
    {
        $model=new Report();$item=$model->find((int)$request->params['id']);if(!$item)Response::error('Report not found',404);$this->assertOwner($request,$item);
        $file=$this->reportFile($item);
        if(!$file){
            $format=strtolower(pathinfo((string)$item['file_path'],PATHINFO_EXTENSION));if(!in_array($format,['pdf','xlsx'],true))$format='pdf';
            $path=(new ReportGenerator())->generate($item['report_type'],$format,null,null,null,$item['generated_by_name']??$request->user['fullname']);
            $model->updatePath((int)$item['id'],$path);
            $item['file_path']=$path;
            $file=$this->reportFile($item);
        }
        if(!$file)Response::error('Report file is unavailable',404);
        $extension=strtolower(pathinfo($file,PATHINFO_EXTENSION));header('Content-Type: '.($extension==='pdf'?'application/pdf':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));header('Content-Disposition: attachment; filename="'.basename($file).'"');header('Content-Length: '.filesize($file));readfile($file);exit;
    }
    public function destroy(Request $request): never
    {
        $id=(int)$request->params['id'];$model=new Report();$item=$model->find($id);if(!$item)Response::error('Report not found',404);$this->assertOwner($request,$item);$file=BASE_PATH.'/'.$item['file_path'];if(is_file($file))unlink($file);$model->delete($id);Response::success(['message'=>'Report deleted']);
    }
    private function assertOwner(Request $request,array $item): void { if($request->user['role']==='subadmin'&&(int)$item['generated_by']!==(int)$request->user['id'])Response::error('Forbidden',403); }
    private function date(string $value): bool { $date=\DateTimeImmutable::createFromFormat('Y-m-d',$value);return $date&&$date->format('Y-m-d')===$value; }
    private function reportFile(array $item): ?string
    {
        $storage=realpath(BASE_PATH.'/storage/reports');$file=realpath(BASE_PATH.'/'.$item['file_path']);
        return $storage&&$file&&str_starts_with($file,$storage.DIRECTORY_SEPARATOR)&&is_file($file)?$file:null;
    }
}
