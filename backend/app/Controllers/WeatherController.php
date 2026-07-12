<?php
namespace App\Controllers;

use App\Core\{Database, Request, Response};

final class WeatherController
{
    private const CONDITIONS=[0=>'Clear sky',1=>'Mainly clear',2=>'Partly cloudy',3=>'Overcast',45=>'Fog',48=>'Rime fog',51=>'Light drizzle',53=>'Drizzle',55=>'Heavy drizzle',61=>'Light rain',63=>'Rain',65=>'Heavy rain',71=>'Light snow',73=>'Snow',75=>'Heavy snow',80=>'Rain showers',81=>'Rain showers',82=>'Heavy rain showers',95=>'Thunderstorm',96=>'Thunderstorm with hail',99=>'Severe thunderstorm with hail'];
    private const RANK=['normal'=>0,'advisory'=>1,'warning'=>2,'critical'=>3];

    public function current(Request $r): never
    {
        [$lat,$lng,$location,$address]=$this->location($r);$query=http_build_query(['latitude'=>$lat,'longitude'=>$lng,'current'=>'temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,rain,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_gusts_10m','hourly'=>'precipitation_probability,precipitation,weather_code,wind_gusts_10m','forecast_days'=>2,'timezone'=>'auto']);$url=rtrim((string)env('WEATHER_API_URL','https://api.open-meteo.com/v1/forecast'),'?').'?'.$query;$context=stream_context_create(['http'=>['timeout'=>10,'header'=>"User-Agent: DisasterMap/1.0\r\n"]]);$raw=@file_get_contents($url,false,$context);$data=$raw?json_decode($raw,true):null;if(!is_array($data)||!isset($data['current'],$data['hourly']))Response::error('Weather service is temporarily unavailable',503);
        $current=$data['current'];$hourly=$data['hourly'];$start=$this->hourlyStart($hourly['time']??[],(string)($current['time']??''));$precip=array_map('floatval',array_slice($hourly['precipitation']??[],$start,6));$prob=array_map('intval',array_slice($hourly['precipitation_probability']??[],$start,6));$codes=array_map('intval',array_slice($hourly['weather_code']??[],$start,6));$gusts=array_map('floatval',array_slice($hourly['wind_gusts_10m']??[],$start,6));
        $rainTotal=array_sum($precip);$maxProbability=$prob?max($prob):0;$rain=$this->rainfall($rainTotal,$maxProbability);$thunder=$this->thunderstorm($codes);$maxGust=max([(float)($current['wind_gusts_10m']??0),...$gusts]);$cyclone=$this->cyclone($maxGust);$advisories=['rainfall'=>$rain,'thunderstorm'=>$thunder,'tropical_cyclone'=>$cyclone];$level='normal';foreach($advisories as $item)if(self::RANK[$item['level']]>self::RANK[$level])$level=$item['level'];$code=(int)($current['weather_code']??-1);
        Response::success(['location'=>['name'=>$location,'address'=>$address,'latitude'=>$lat,'longitude'=>$lng,'timezone'=>$data['timezone']??'UTC'],'current'=>['condition'=>self::CONDITIONS[$code]??'Unknown','weather_code'=>$code,'temperature_c'=>(float)($current['temperature_2m']??0),'apparent_temperature_c'=>(float)($current['apparent_temperature']??0),'humidity_percent'=>(int)($current['relative_humidity_2m']??0),'precipitation_mm'=>(float)($current['precipitation']??0),'wind_speed_kmh'=>(float)($current['wind_speed_10m']??0),'wind_gust_kmh'=>(float)($current['wind_gusts_10m']??0),'cloud_cover_percent'=>(int)($current['cloud_cover']??0),'pressure_hpa'=>(float)($current['pressure_msl']??0)],'warning_level'=>$level,'advisories'=>$advisories,'last_updated'=>$current['time']??gmdate(DATE_ATOM),'source'=>'Open-Meteo','official_notice'=>'Derived weather guidance only. Follow PAGASA and local DRRMO bulletins for official tropical cyclone signals and evacuation orders.']);
    }
    private function location(Request $r): array
    {
        $lat=filter_var($r->query('latitude'),FILTER_VALIDATE_FLOAT);$lng=filter_var($r->query('longitude'),FILTER_VALIDATE_FLOAT);if($lat!==false&&$lng!==false&&abs((float)$lat)<=90&&abs((float)$lng)<=180){$lat=(float)$lat;$lng=(float)$lng;return [$lat,$lng,'Current location',$this->reverseGeocode($lat,$lng)??'Current location'];}
        if($r->user['municipality_id']){$s=Database::connection()->prepare('SELECT municipality_name,center_lat,center_lng FROM municipalities WHERE id=?');$s->execute([$r->user['municipality_id']]);$m=$s->fetch();if($m&&$m['center_lat']!==null){$lat=(float)$m['center_lat'];$lng=(float)$m['center_lng'];return [$lat,$lng,$m['municipality_name'],$this->reverseGeocode($lat,$lng)??$m['municipality_name']];}}
        $lat=(float)env('WEATHER_DEFAULT_LAT',14.5995);$lng=(float)env('WEATHER_DEFAULT_LNG',120.9842);return [$lat,$lng,'Default monitoring location',$this->reverseGeocode($lat,$lng)??'Default monitoring location'];
    }
    private function reverseGeocode(float $lat,float $lng): ?string
    {
        $endpoint=rtrim((string)env('GEOCODING_REVERSE_URL','https://nominatim.openstreetmap.org/reverse'),'?');$url=$endpoint.'?'.http_build_query(['format'=>'jsonv2','lat'=>$lat,'lon'=>$lng,'zoom'=>18,'addressdetails'=>1]);$context=stream_context_create(['http'=>['timeout'=>4,'header'=>"User-Agent: DisasterMap/1.0\r\nAccept: application/json\r\n"]]);$raw=@file_get_contents($url,false,$context);$data=$raw?json_decode($raw,true):null;$address=is_array($data)?trim((string)($data['display_name']??'')):'';return $address!==''?$address:null;
    }
    private function hourlyStart(array $times,string $current): int { foreach($times as $i=>$time)if($time>=$current)return $i;return 0; }
    private function rainfall(float $total,int $probability): array
    {
        if($total>=30)return ['title'=>'Rainfall Advisory','level'=>'critical','message'=>'Very heavy rainfall is forecast in the next 6 hours. Flooding and landslides may occur.','forecast_6h_mm'=>round($total,1),'max_probability_percent'=>$probability];if($total>=15)return ['title'=>'Rainfall Advisory','level'=>'warning','message'=>'Heavy rainfall is forecast. Monitor flood-prone and landslide-prone areas.','forecast_6h_mm'=>round($total,1),'max_probability_percent'=>$probability];if($total>=5||$probability>=70)return ['title'=>'Rainfall Advisory','level'=>'advisory','message'=>'Rain is likely. Carry rain protection and monitor local advisories.','forecast_6h_mm'=>round($total,1),'max_probability_percent'=>$probability];return ['title'=>'Rainfall Advisory','level'=>'normal','message'=>'No significant rainfall signal in the next 6 hours.','forecast_6h_mm'=>round($total,1),'max_probability_percent'=>$probability];
    }
    private function thunderstorm(array $codes): array { $severe=array_intersect($codes,[96,99]);$storm=array_intersect($codes,[95,96,99]);if($severe)return ['title'=>'Thunderstorm Advisory','level'=>'critical','message'=>'Severe thunderstorm or hail is forecast. Stay indoors and avoid exposed areas.'];if($storm)return ['title'=>'Thunderstorm Advisory','level'=>'warning','message'=>'Thunderstorm conditions are forecast within 6 hours. Avoid open fields, waterways, and isolated trees.'];return ['title'=>'Thunderstorm Advisory','level'=>'normal','message'=>'No thunderstorm signal in the next 6 hours.']; }
    private function cyclone(float $gust): array
    {
        if($gust>=118)$level='critical';elseif($gust>=89)$level='warning';elseif($gust>=62)$level='advisory';else$level='normal';$message=$level==='normal'?'No damaging-wind signal in this forecast. This does not confirm the absence of a tropical cyclone.':'Strong to destructive wind is indicated. Secure loose objects and check official PAGASA tropical cyclone bulletins.';return ['title'=>'Tropical Cyclone Advisory','level'=>$level,'message'=>$message,'maximum_gust_6h_kmh'=>round($gust,1),'official_confirmation'=>false];
    }
}
