<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response};

final class AdminController
{
    public function stats(Request $r): never {
        $db=Database::connection(); $scope=$r->user['role']==='subadmin'?' AND municipality_id='.(int)$r->user['municipality_id']:'';
        $data=['active_hazards'=>(int)$db->query('SELECT COUNT(*) FROM hazards WHERE status="active"'.$scope)->fetchColumn(),'active_alerts'=>(int)$db->query('SELECT COUNT(*) FROM alerts WHERE status="sent"'.$scope)->fetchColumn(),'residents'=>(int)$db->query('SELECT COUNT(*) FROM users WHERE role="resident" AND status="active"'.$scope)->fetchColumn(),'municipalities'=>(int)$db->query('SELECT COUNT(*) FROM municipalities WHERE status="active"')->fetchColumn()];
        Response::success($data);
    }
}
