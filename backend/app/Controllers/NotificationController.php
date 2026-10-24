<?php
namespace App\Controllers;

use App\Core\{Request, Response};
use App\Models\{Alert, Notification};

/** Merges the public "alerts" broadcast feed with per-user system notifications
 *  (e.g. hazard/safe zone creation notices) into the single bell the frontend polls. */
final class NotificationController
{
    public function history(Request $r): never
    {
        $userId=(int)$r->user['id'];$mid=$r->user['municipality_id']?(int)$r->user['municipality_id']:null;
        $alerts=array_map(fn($a)=>['id'=>$a['id'],'kind'=>'alert','title'=>$a['title'],'message'=>$a['message'],'alert_level'=>$a['alert_level'],'alert_type'=>$a['alert_type'],'municipality_id'=>$a['municipality_id']===null?null:(int)$a['municipality_id'],'municipality_name'=>$a['municipality_name']??null,'is_read'=>$a['is_read'],'sent_at'=>$a['sent_at']],(new Alert())->history($userId,$mid));
        $system=array_map(fn($n)=>['id'=>'sys-'.$n['id'],'kind'=>$n['notification_type']==='announcement'?'coordination':'system','title'=>$n['title'],'message'=>$n['message'],'is_read'=>$n['is_read'],'sent_at'=>$n['created_at']],(new Notification())->history($userId));
        $merged=array_merge($alerts,$system);
        usort($merged,fn($a,$b)=>strcmp((string)$b['sent_at'],(string)$a['sent_at']));
        Response::success(array_slice($merged,0,100));
    }
    public function unreadCount(Request $r): never
    {
        $userId=(int)$r->user['id'];$mid=$r->user['municipality_id']?(int)$r->user['municipality_id']:null;
        Response::success(['count'=>(new Alert())->unreadCount($userId,$mid)+(new Notification())->unreadCount($userId)]);
    }
    public function markRead(Request $r): never
    {
        $id=(string)$r->params['id'];$userId=(int)$r->user['id'];
        if(str_starts_with($id,'sys-')){(new Notification())->markRead((int)substr($id,4),$userId);Response::success(['message'=>'Notification marked as read']);}
        $alertId=(int)$id;$item=(new Alert())->find($alertId);if(!$item)Response::error('Alert not found',404);
        if($item['status']!=='sent'||($item['municipality_id']!==null&&(int)$item['municipality_id']!==(int)$r->user['municipality_id']))Response::error('Alert is not available to this user',403);
        (new Alert())->markRead($alertId,$userId);Response::success(['message'=>'Alert marked as read']);
    }
}
