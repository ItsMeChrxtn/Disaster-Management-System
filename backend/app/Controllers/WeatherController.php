<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response};

final class WeatherController
{
    private const CONDITIONS=[0=>'Clear sky',1=>'Mainly clear',2=>'Partly cloudy',3=>'Overcast',45=>'Fog',48=>'Rime fog',51=>'Light drizzle',53=>'Drizzle',55=>'Heavy drizzle',61=>'Light rain',63=>'Rain',65=>'Heavy rain',71=>'Light snow',73=>'Snow',75=>'Heavy snow',80=>'Rain showers',81=>'Rain showers',82=>'Heavy rain showers',95=>'Thunderstorm',96=>'Thunderstorm with hail',99=>'Severe thunderstorm with hail'];
    private const RANK=['normal'=>0,'advisory'=>1,'warning'=>2,'critical'=>3];
    private const CURRENT_FIELDS='temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,rain,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_gusts_10m';
    private const HOURLY_FIELDS='precipitation_probability,precipitation,weather_code,wind_gusts_10m';
    private const AIR_FIELDS='us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide';
    // PAGASA Heavy Rainfall Warning System thresholds (mm of rain per hour).
    private const RAINFALL_WARNINGS=[
        'red'=>['min'=>30,'label'=>'Red rainfall warning','meaning'=>'Torrential rain (more than 30 mm/hr). Serious flooding is expected in low-lying areas.','action'=>'EVACUATE. Move to evacuation centers or higher ground now.'],
        'orange'=>['min'=>15,'label'=>'Orange rainfall warning','meaning'=>'Intense rain (15-30 mm/hr). Flooding is threatening.','action'=>'Be alert and prepare for possible evacuation.'],
        'yellow'=>['min'=>7.5,'label'=>'Yellow rainfall advisory','meaning'=>'Heavy rain (7.5-15 mm/hr). Flooding is possible in low-lying areas and near rivers.','action'=>'Monitor the weather and stay alert.'],
        'none'=>['min'=>0,'label'=>'No rainfall warning','meaning'=>'Less than 7.5 mm/hr of rain observed or expected.','action'=>'No action needed. Continue normal activities.'],
    ];

    public function current(Request $r): never
    {
        [$lat,$lng,$location,$address]=$this->location($r);
        $data=$this->fetchCached($this->forecastUrl([$lat],[$lng]),300,10);
        if(!is_array($data)||!isset($data['current'],$data['hourly']))Response::error('Weather service is temporarily unavailable',503);
        $air=$this->fetchCached($this->airUrl([$lat],[$lng]),900,8);
        $summary=$this->summarize($data,is_array($air)?($air['current']??null):null);
        Response::success(['location'=>['name'=>$location,'address'=>$address,'latitude'=>$lat,'longitude'=>$lng,'timezone'=>$data['timezone']??'UTC']]+$summary+['source'=>'Open-Meteo','official_notice'=>'Derived weather guidance only. Follow PAGASA and local DRRMO bulletins for official tropical cyclone signals and evacuation orders.']);
    }

    // Current conditions for every active municipality in one batched request.
    public function municipalities(Request $r): never
    {
        $sql='SELECT id,municipality_name,center_lat,center_lng FROM municipalities WHERE status="active" AND center_lat IS NOT NULL AND center_lng IS NOT NULL';
        if($r->user['role']==='resident'&&$r->user['municipality_id'])$sql.=' AND id='.(int)$r->user['municipality_id'];
        $rows=Database::connection()->query($sql.' ORDER BY municipality_name')->fetchAll();
        if(!$rows)Response::success(['municipalities'=>[],'summary'=>$this->rollup([]),'generated_at'=>gmdate(DATE_ATOM),'source'=>'Open-Meteo']);
        $lats=array_map(fn($row)=>round((float)$row['center_lat'],4),$rows);$lngs=array_map(fn($row)=>round((float)$row['center_lng'],4),$rows);
        $forecast=$this->fetchCached($this->forecastUrl($lats,$lngs),600,15);
        if(!is_array($forecast))Response::error('Weather service is temporarily unavailable',503);
        if(isset($forecast['current']))$forecast=[$forecast];
        $air=$this->fetchCached($this->airUrl($lats,$lngs),900,12);
        if(is_array($air)&&isset($air['current']))$air=[$air];
        $items=[];
        foreach($rows as $i=>$row){
            $data=$forecast[$i]??null;if(!is_array($data)||!isset($data['current'],$data['hourly']))continue;
            $summary=$this->summarize($data,is_array($air)&&isset($air[$i]['current'])?$air[$i]['current']:null);
            $items[]=['id'=>(int)$row['id'],'municipality_name'=>$row['municipality_name'],'latitude'=>(float)$row['center_lat'],'longitude'=>(float)$row['center_lng']]+$summary;
        }
        Response::success(['municipalities'=>$items,'summary'=>$this->rollup($items),'generated_at'=>gmdate(DATE_ATOM),'source'=>'Open-Meteo forecast and air-quality APIs']);
    }

    private function forecastUrl(array $lats,array $lngs): string
    {
        $query=http_build_query(['latitude'=>implode(',',$lats),'longitude'=>implode(',',$lngs),'current'=>self::CURRENT_FIELDS,'hourly'=>self::HOURLY_FIELDS,'forecast_days'=>2,'timezone'=>'Asia/Manila']);
        return rtrim((string)env('WEATHER_API_URL','https://api.open-meteo.com/v1/forecast'),'?').'?'.$query;
    }
    private function airUrl(array $lats,array $lngs): string
    {
        $query=http_build_query(['latitude'=>implode(',',$lats),'longitude'=>implode(',',$lngs),'current'=>self::AIR_FIELDS,'timezone'=>'Asia/Manila']);
        return rtrim((string)env('AIR_QUALITY_API_URL','https://air-quality-api.open-meteo.com/v1/air-quality'),'?').'?'.$query;
    }

    private function summarize(array $data,?array $airCurrent): array
    {
        $current=$data['current'];$hourly=$data['hourly'];$start=$this->hourlyStart($hourly['time']??[],(string)($current['time']??''));
        $precip=array_map('floatval',array_slice($hourly['precipitation']??[],$start,6));$prob=array_map('intval',array_slice($hourly['precipitation_probability']??[],$start,6));$codes=array_map('intval',array_slice($hourly['weather_code']??[],$start,6));$gusts=array_map('floatval',array_slice($hourly['wind_gusts_10m']??[],$start,6));
        $rainTotal=array_sum($precip);$maxProbability=$prob?max($prob):0;
        $hourlyRate=max([(float)($current['precipitation']??0),...array_slice($precip,0,3)]);
        $rainfallWarning=$this->rainfallWarning($hourlyRate);
        $rain=$this->rainfall($rainTotal,$maxProbability,$rainfallWarning);$thunder=$this->thunderstorm($codes);$maxGust=max([(float)($current['wind_gusts_10m']??0),...$gusts]);$cyclone=$this->cyclone($maxGust);
        $advisories=['rainfall'=>$rain,'thunderstorm'=>$thunder,'tropical_cyclone'=>$cyclone];$airQuality=$this->airQuality($airCurrent);
        if($airQuality)$advisories['air_quality']=['title'=>'Air Quality Advisory','level'=>$airQuality['level'],'message'=>$airQuality['advice'],'us_aqi'=>$airQuality['us_aqi'],'category'=>$airQuality['category']];
        $level='normal';foreach($advisories as $item)if(self::RANK[$item['level']]>self::RANK[$level])$level=$item['level'];$code=(int)($current['weather_code']??-1);
        return ['current'=>['condition'=>self::CONDITIONS[$code]??'Unknown','weather_code'=>$code,'is_day'=>(int)($current['is_day']??1)===1,'temperature_c'=>(float)($current['temperature_2m']??0),'apparent_temperature_c'=>(float)($current['apparent_temperature']??0),'humidity_percent'=>(int)($current['relative_humidity_2m']??0),'precipitation_mm'=>(float)($current['precipitation']??0),'wind_speed_kmh'=>(float)($current['wind_speed_10m']??0),'wind_gust_kmh'=>(float)($current['wind_gusts_10m']??0),'cloud_cover_percent'=>(int)($current['cloud_cover']??0),'pressure_hpa'=>(float)($current['pressure_msl']??0)],'warning_level'=>$level,'rainfall_warning'=>$rainfallWarning,'air_quality'=>$airQuality,'advisories'=>$advisories,'last_updated'=>$current['time']??gmdate(DATE_ATOM)];
    }

    private function rainfallWarning(float $mmPerHour): array
    {
        foreach(self::RAINFALL_WARNINGS as $color=>$warning)if($mmPerHour>=$warning['min'])return ['color'=>$color,'label'=>$warning['label'],'meaning'=>$warning['meaning'],'action'=>$warning['action'],'mm_per_hour'=>round($mmPerHour,1)];
        return ['color'=>'none']+self::RAINFALL_WARNINGS['none']+['mm_per_hour'=>0];
    }

    // US EPA AQI bands with face-mask guidance.
    private function airQuality(?array $air): ?array
    {
        if(!$air||!isset($air['us_aqi']))return null;$aqi=(int)round((float)$air['us_aqi']);
        $bands=[
            [50,'Good','#16a34a','normal','none','Air quality is good. No face mask needed.'],
            [100,'Moderate','#ca8a04','normal','none','Air quality is acceptable. Unusually sensitive people should limit long outdoor exertion.'],
            [150,'Unhealthy for sensitive groups','#ea580c','advisory','sensitive','Children, older adults, pregnant women and people with asthma, lung or heart disease should WEAR A FACE MASK outdoors and limit outdoor activity.'],
            [200,'Unhealthy','#dc2626','warning','everyone','Everyone should WEAR A FACE MASK (KN95/N95) outdoors and reduce outdoor activity. Sensitive groups should stay indoors.'],
            [300,'Very unhealthy','#7e22ce','critical','everyone','Health alert: WEAR AN N95 FACE MASK if you must go out. Stay indoors with windows closed.'],
            [PHP_INT_MAX,'Hazardous','#7f1d1d','critical','everyone','Health emergency: stay indoors, keep windows closed and wear an N95 face mask if going outside is unavoidable.'],
        ];
        foreach($bands as [$max,$category,$color,$level,$mask,$advice])if($aqi<=$max)break;
        return ['us_aqi'=>$aqi,'category'=>$category,'color'=>$color,'level'=>$level,'mask'=>$mask,'advice'=>$advice,'pm2_5'=>isset($air['pm2_5'])?round((float)$air['pm2_5'],1):null,'pm10'=>isset($air['pm10'])?round((float)$air['pm10'],1):null,'ozone'=>isset($air['ozone'])?round((float)$air['ozone'],1):null,'sulphur_dioxide'=>isset($air['sulphur_dioxide'])?round((float)$air['sulphur_dioxide'],1):null,'nitrogen_dioxide'=>isset($air['nitrogen_dioxide'])?round((float)$air['nitrogen_dioxide'],1):null];
    }

    private function rollup(array $items): array
    {
        $summary=['rainfall'=>['red'=>0,'orange'=>0,'yellow'=>0,'none'=>0],'warning_levels'=>['critical'=>0,'warning'=>0,'advisory'=>0,'normal'=>0],'mask_advisories'=>0,'worst_aqi'=>null];
        foreach($items as $item){
            $summary['rainfall'][$item['rainfall_warning']['color']]++;$summary['warning_levels'][$item['warning_level']]++;
            if(($item['air_quality']['mask']??'none')!=='none')$summary['mask_advisories']++;
            if($item['air_quality']&&($summary['worst_aqi']===null||$item['air_quality']['us_aqi']>$summary['worst_aqi']['us_aqi']))$summary['worst_aqi']=['us_aqi'=>$item['air_quality']['us_aqi'],'category'=>$item['air_quality']['category'],'municipality_name'=>$item['municipality_name']];
        }
        return $summary;
    }

    private function location(Request $r): array
    {
        $lat=filter_var($r->query('latitude'),FILTER_VALIDATE_FLOAT);$lng=filter_var($r->query('longitude'),FILTER_VALIDATE_FLOAT);if($lat!==false&&$lng!==false&&abs((float)$lat)<=90&&abs((float)$lng)<=180){$lat=(float)$lat;$lng=(float)$lng;return [$lat,$lng,'Current location',$this->reverseGeocode($lat,$lng)??'Current location'];}
        if($r->user['municipality_id']){$s=Database::connection()->prepare('SELECT municipality_name,center_lat,center_lng FROM municipalities WHERE id=?');$s->execute([$r->user['municipality_id']]);$m=$s->fetch();if($m&&$m['center_lat']!==null){$lat=(float)$m['center_lat'];$lng=(float)$m['center_lng'];return [$lat,$lng,$m['municipality_name'],$this->reverseGeocode($lat,$lng)??$m['municipality_name']];}}
        $lat=(float)env('WEATHER_DEFAULT_LAT',14.5995);$lng=(float)env('WEATHER_DEFAULT_LNG',120.9842);return [$lat,$lng,'Default monitoring location',$this->reverseGeocode($lat,$lng)??'Default monitoring location'];
    }
    private function reverseGeocode(float $lat,float $lng): ?string
    {
        $endpoint=rtrim((string)env('GEOCODING_REVERSE_URL','https://nominatim.openstreetmap.org/reverse'),'?');$url=$endpoint.'?'.http_build_query(['format'=>'jsonv2','lat'=>round($lat,4),'lon'=>round($lng,4),'zoom'=>18,'addressdetails'=>1]);
        $data=$this->fetchCached($url,86400,4);$address=is_array($data)?trim((string)($data['display_name']??'')):'';return $address!==''?$address:null;
    }
    // Small file cache keeps the free upstream APIs within their rate limits.
    private function fetchCached(string $url,int $ttl,int $timeoutSeconds): ?array
    {
        $dir=BASE_PATH.'/storage/cache';$file=$dir.'/'.md5($url).'.json';
        if(is_file($file)&&filemtime($file)>time()-$ttl){$cached=json_decode((string)file_get_contents($file),true);if(is_array($cached))return $cached;}
        $data=$this->fetchJson($url,$timeoutSeconds)??$this->fetchJson($url,$timeoutSeconds);
        if(is_array($data)&&!isset($data['error'])){if(!is_dir($dir))@mkdir($dir,0775,true);@file_put_contents($file,json_encode($data),LOCK_EX);return $data;}
        if(is_file($file)){$stale=json_decode((string)file_get_contents($file),true);if(is_array($stale))return $stale;}
        return null;
    }
    private function fetchJson(string $url,int $timeoutSeconds): ?array
    {
        if(function_exists('curl_init')){
            $ch=curl_init($url);curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>$timeoutSeconds,CURLOPT_CONNECTTIMEOUT=>$timeoutSeconds,CURLOPT_USERAGENT=>'DisasterMap/1.0',CURLOPT_HTTPHEADER=>['Accept: application/json'],CURLOPT_FOLLOWLOCATION=>true,CURLOPT_SSL_VERIFYPEER=>true]);
            $raw=curl_exec($ch);$status=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);
            if($raw!==false&&$status===200){$decoded=json_decode($raw,true);if(is_array($decoded))return $decoded;}
        }
        $context=stream_context_create(['http'=>['timeout'=>$timeoutSeconds,'header'=>"User-Agent: DisasterMap/1.0\r\nAccept: application/json\r\n"]]);
        $raw=@file_get_contents($url,false,$context);$decoded=$raw?json_decode($raw,true):null;return is_array($decoded)?$decoded:null;
    }
    private function hourlyStart(array $times,string $current): int { foreach($times as $i=>$time)if($time>=$current)return $i;return 0; }
    private function rainfall(float $total,int $probability,array $warning): array
    {
        $base=['title'=>'Rainfall Advisory','forecast_6h_mm'=>round($total,1),'max_probability_percent'=>$probability,'rainfall_color'=>$warning['color'],'mm_per_hour'=>$warning['mm_per_hour']];
        if($warning['color']==='red'||$total>=30)return $base+['level'=>'critical','message'=>$warning['color']==='red'?$warning['meaning'].' '.$warning['action']:'Very heavy rainfall is forecast in the next 6 hours. Flooding and landslides may occur.'];
        if($warning['color']==='orange'||$total>=15)return $base+['level'=>'warning','message'=>$warning['color']==='orange'?$warning['meaning'].' '.$warning['action']:'Heavy rainfall is forecast. Monitor flood-prone and landslide-prone areas.'];
        if($warning['color']==='yellow'||$total>=5||$probability>=70)return $base+['level'=>'advisory','message'=>$warning['color']==='yellow'?$warning['meaning'].' '.$warning['action']:'Rain is likely. Carry rain protection and monitor local advisories.'];
        return $base+['level'=>'normal','message'=>'No significant rainfall signal in the next 6 hours.'];
    }
    private function thunderstorm(array $codes): array { $severe=array_intersect($codes,[96,99]);$storm=array_intersect($codes,[95,96,99]);if($severe)return ['title'=>'Thunderstorm Advisory','level'=>'critical','message'=>'Severe thunderstorm or hail is forecast. Stay indoors and avoid exposed areas.'];if($storm)return ['title'=>'Thunderstorm Advisory','level'=>'warning','message'=>'Thunderstorm conditions are forecast within 6 hours. Avoid open fields, waterways, and isolated trees.'];return ['title'=>'Thunderstorm Advisory','level'=>'normal','message'=>'No thunderstorm signal in the next 6 hours.']; }
    private function cyclone(float $gust): array
    {
        if($gust>=118)$level='critical';elseif($gust>=89)$level='warning';elseif($gust>=62)$level='advisory';else$level='normal';$message=$level==='normal'?'No damaging-wind signal in this forecast. This does not confirm the absence of a tropical cyclone.':'Strong to destructive wind is indicated. Secure loose objects and check official PAGASA tropical cyclone bulletins.';return ['title'=>'Tropical Cyclone Advisory','level'=>$level,'message'=>$message,'maximum_gust_6h_kmh'=>round($gust,1),'official_confirmation'=>false];
    }
}
