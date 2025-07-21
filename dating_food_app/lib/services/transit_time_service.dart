import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class TransitTimeService {
  static final TransitTimeService _instance = TransitTimeService._internal();
  factory TransitTimeService() => _instance;
  TransitTimeService._internal();

  // Google Maps APIキー（実際の環境では環境変数から取得）
  static const String _apiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
  
  // 公共交通機関での所要時間を計算（徒歩含む）
  Future<String?> getTransitTime({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    try {
      final String url = 'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$fromLat,$fromLng'
          '&destinations=$toLat,$toLng'
          '&mode=transit'
          '&language=ja'
          '&departure_time=now'
          '&key=$_apiKey';

      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && 
            data['rows'] != null && 
            data['rows'].isNotEmpty &&
            data['rows'][0]['elements'] != null &&
            data['rows'][0]['elements'].isNotEmpty) {
          
          final element = data['rows'][0]['elements'][0];
          
          if (element['status'] == 'OK' && element['duration'] != null) {
            final durationText = element['duration']['text'] as String;
            return durationText;
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  // 現在地から複数の目的地への所要時間を一括取得
  Future<Map<String, String>> getMultipleTransitTimes({
    required Position userPosition,
    required List<Map<String, dynamic>> destinations,
  }) async {
    final results = <String, String>{};
    
    // APIの制限を考慮して、少し間隔を開けて処理
    for (final destination in destinations) {
      final id = destination['id'] as String;
      final lat = destination['lat'] as double;
      final lng = destination['lng'] as double;
      
      final transitTime = await getTransitTime(
        fromLat: userPosition.latitude,
        fromLng: userPosition.longitude,
        toLat: lat,
        toLng: lng,
      );
      
      if (transitTime != null) {
        results[id] = transitTime;
      }
      
      // API制限回避のため少し待機
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return results;
  }

  // 距離に基づく簡易所要時間推定（徒歩+電車+乗り換え込み）
  String estimateTransitTime(double distanceKm) {
    // 基本的な徒歩時間（駅まで + 駅から）
    int walkingMinutes = 10; // 往復で約10分
    
    // 電車での移動時間（平均速度約30km/h + 停車時間）
    int trainMinutes = (distanceKm * 2.5).round(); // 1kmあたり2.5分
    
    // 乗り換え時間（距離に応じて）
    int transferMinutes = 0;
    if (distanceKm > 8) {
      transferMinutes = 5; // 1回乗り換え
    }
    if (distanceKm > 20) {
      transferMinutes = 10; // 2回乗り換え
    }
    
    // 待ち時間（電車の間隔）
    int waitingMinutes = distanceKm <= 3 ? 3 : 5;
    
    final totalMinutes = walkingMinutes + trainMinutes + transferMinutes + waitingMinutes + 4; // +4分の調整
    
    if (totalMinutes <= 60) {
      return '約${totalMinutes}分';
    } else {
      final hours = (totalMinutes / 60).floor();
      final minutes = totalMinutes % 60;
      if (minutes == 0) {
        return '約${hours}時間';
      } else {
        return '約${hours}時間${minutes}分';
      }
    }
  }
} 