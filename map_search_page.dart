import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/restaurant_model.dart';
import '../models/group_model.dart';
import '../services/group_service.dart';
import '../services/transit_time_service.dart';
import 'group_chat_page.dart';
import 'profile_view_page.dart';

class MapSearchPage extends StatefulWidget {
  const MapSearchPage({super.key});

  @override
  State<MapSearchPage> createState() => _MapSearchPageState();
}

class _MapSearchPageState extends State<MapSearchPage> {
  GoogleMapController? _mapController;
  final Completer<GoogleMapController> _controller = Completer();
  final GroupService _groupService = GroupService();
  final TransitTimeService _transitTimeService = TransitTimeService();
  
  // 初期位置（東京駅）
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(35.6812, 139.7671),
    zoom: 12.0,
  );
  
  // レストランデータ
  List<Restaurant> _restaurants = [];
  Set<Marker> _markers = {};
  bool _isLoading = true;
  bool _isLoadingLocation = false;
  bool _hasApiKeyError = false;
  Position? _currentPosition;
  
  // レストラン募集グループデータ
  List<Group> _restaurantGroups = [];
  Map<String, String> _transitTimes = {}; // グループIDと所要時間のマップ
  StreamSubscription<List<Group>>? _restaurantGroupsSubscription;
  
  // フィルター用
  List<String> _selectedCategories = [];
  List<String> _selectedPrefectures = [];
  RangeValues _priceRange = const RangeValues(1000, 5000);
  
  // カテゴリオプション
  static const List<String> _categories = [
    '居酒屋', 'カラオケ・パーティ', 'バー・カクテル', 'ラーメン', '和食', '韓国料理',
    'カフェ・スイーツ', '焼肉・ホルモン', 'アジア・エスニック料理', '洋食', '中華',
    'ダイニングバー・バル', 'イタリアン・フレンチ', 'その他グルメ', 'お好み焼き・もんじゃ',
    '各国料理', '創作料理',
  ];

  // デバウンス用
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 800);
  
  // いいね機能用
  Set<String> _likedRestaurants = {};

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
    _getCurrentLocation();
    _loadUserLikes();
    _loadRestaurantGroups();
  }

  // 現在地取得（権限チェック込み）
  Future<void> _getCurrentLocation() async {
    // Web版では現在地取得をスキップ
    if (kIsWeb) {
      setState(() {
        _isLoadingLocation = false;
      });
      print('🌐 Web版では現在地取得をスキップします');
      return;
    }

    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // サービスが有効かチェック
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('位置情報サービスが無効です')),
          );
        }
        return;
      }

      // 権限をチェック
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('位置情報の権限が拒否されました')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('位置情報の権限が永続的に拒否されています。設定から有効にしてください'),
            ),
          );
        }
        return;
      }

      // 現在地を取得
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      setState(() {
        _currentPosition = position;
      });

      // 地図を現在地に移動
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 15.0,
            ),
          ),
        );
      }

      // 所要時間を計算（徒歩+電車+乗り換え込み）
      _calculateTransitTimes();
      
      // 既存のグループがある場合は、そのマーカーも更新
      if (_restaurantGroups.isNotEmpty) {
        _updateMarkersWithGroups();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現在地を取得しました')),
        );
      }
    } catch (e) {
      print('現在地取得エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('現在地取得に失敗しました: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  // レストランデータの読み込み
  Future<void> _loadRestaurants() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('searchRestaurantsWithCoordinates');
      
      // 地図の表示範囲とズームレベルを取得
      LatLngBounds? visibleRegion;
      double? zoom;
      if (_mapController != null) {
        visibleRegion = await _mapController!.getVisibleRegion();
        zoom = await _mapController!.getZoomLevel();
      }

      // ズームレベルに応じて取得件数を調整
      int limit = 100;
      if (zoom != null) {
        if (zoom < 10) { // 広域表示
          limit = 200;  // 主要な店舗のみ
        } else if (zoom < 13) {
          limit = 500;  // やや詳細に
        } else if (zoom < 15) {
          limit = 1000; // より詳細に
        } else {
          limit = 2000; // 最も詳細な表示
        }
      }

      final result = await callable.call({
        'bounds': visibleRegion != null ? {
          'northeast': {
            'lat': visibleRegion.northeast.latitude,
            'lng': visibleRegion.northeast.longitude,
          },
          'southwest': {
            'lat': visibleRegion.southwest.latitude,
            'lng': visibleRegion.southwest.longitude,
          },
        } : null,
        'zoom': zoom,
        'limit': limit,
        'category': _selectedCategories.isNotEmpty ? _selectedCategories.first : null,
        'priceRange': _priceRange.start != 1000 || _priceRange.end != 5000 
            ? '${_priceRange.start.round()}-${_priceRange.end.round()}' 
            : null,
      });

      // データの型を確認
      print('📦 受信データの型: ${result.data.runtimeType}');

      // 結果を確認
      List<dynamic> restaurantData = [];
      int totalCount = 0;

      if (result.data is Map) {
        final Map<Object?, Object?> rawData = result.data as Map<Object?, Object?>;
        if (rawData['restaurants'] != null) {
          restaurantData = (rawData['restaurants'] as List).map((item) {
            if (item is Map<Object?, Object?>) {
              return Map<String, dynamic>.fromEntries(
                item.entries.map((e) => MapEntry(e.key.toString(), e.value))
              );
            }
            return item;
          }).toList();
        }
        totalCount = (rawData['totalCount'] as num?)?.toInt() ?? 0;
      }

      print('📦 変換後のデータ件数: ${restaurantData.length}');
      print('📦 総レストラン件数: $totalCount');
      print('📦 現在のズームレベル: $zoom');
      print('📦 取得制限: $limit件');

      // レストランデータをマッピング
      final restaurants = <Restaurant>[];
      
      for (int i = 0; i < restaurantData.length; i++) {
        final data = restaurantData[i];
        
        try {
          if (data == null) {
            print('⚠️ データ[$i]がnullです');
            continue;
          }

          Map<String, dynamic> restaurantMap;
          if (data is Map<String, dynamic>) {
            restaurantMap = data;
          } else if (data is Map) {
            restaurantMap = Map<String, dynamic>.fromEntries(
              data.entries.map((e) => MapEntry(e.key.toString(), e.value))
            );
          } else {
            print('⚠️ データ[$i]が不正な形式です: ${data.runtimeType}');
            continue;
          }

          final restaurant = Restaurant.fromMap(restaurantMap);
          
          // 座標データの追加チェック
          if (restaurant.latitude != null && restaurant.longitude != null) {
            final lat = restaurant.latitude!;
            final lng = restaurant.longitude!;
            
            // 日本の有効な座標範囲内かチェック
            if (lat >= 24 && lat <= 46 && lng >= 123 && lng <= 146) {
              restaurants.add(restaurant);
            }
          }
        } catch (e, stackTrace) {
          print('❌ レストランデータ変換エラー[$i]: $e');
          print('❌ データタイプ: ${data.runtimeType}');
          print('❌ データ内容: $data');
          print('❌ スタックトレース: $stackTrace');
          continue;
        }
      }

      setState(() {
        _restaurants = restaurants;
        _isLoading = false;
      });

      // マーカーを更新
      await _updateMarkers();

      // 統計情報を表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('表示中: ${restaurants.length}件 / 総数: $totalCount件'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ レストランデータ読み込みエラー: $e');
      print('❌ スタックトレース: $stackTrace');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('レストランデータの読み込みに失敗しました'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // マーカーの更新
  Future<void> _updateMarkers() async {
    if (_restaurants.isEmpty) return;

    final Set<Marker> markers = {};
    final bounds = await _mapController?.getVisibleRegion();
    
    for (final restaurant in _restaurants) {
      if (restaurant.latitude == null || restaurant.longitude == null) continue;
      
      final position = LatLng(restaurant.latitude!, restaurant.longitude!);
      
      // 表示範囲外のレストランはスキップ
      if (bounds != null && !_isInBounds(position, bounds)) continue;

      markers.add(
        Marker(
          markerId: MarkerId('restaurant_${restaurant.id}'), // プレフィックスを追加
          position: position,
          onTap: () => _showRestaurantDetail(restaurant),
          icon: await _getMarkerIcon(_getCategoryColor(restaurant.category)),
          zIndex: 100.0, // 募集マーカーより下に表示
        ),
      );
    }

    // 既存のグループマーカーを保持
    final existingGroupMarkers = _markers
        .where((marker) => marker.markerId.value.startsWith('group_'))
        .toSet();
    
    print('🔍 レストラン更新: 新しいレストランマーカー数=${markers.length}');
    print('🔍 レストラン更新: 既存グループマーカー数=${existingGroupMarkers.length}');
    
    // レストランマーカーとグループマーカーを結合
    final allMarkers = Set<Marker>.from(markers);
    allMarkers.addAll(existingGroupMarkers);
    
    print('🔍 レストラン更新: 結合後の総マーカー数=${allMarkers.length}');

    setState(() {
      _markers = allMarkers;
    });
  }

  // 座標が表示範囲内かチェック
  bool _isInBounds(LatLng position, LatLngBounds bounds) {
    return position.latitude >= bounds.southwest.latitude &&
           position.latitude <= bounds.northeast.latitude &&
           position.longitude >= bounds.southwest.longitude &&
           position.longitude <= bounds.northeast.longitude;
  }

  // マーカーアイコンの生成（シンプルなピン形状）
  Future<BitmapDescriptor> _getMarkerIcon(Color color) async {
    const size = 120;
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    
    final paint = Paint()..color = color;
    
    // ピン形状を描画
    final path = Path();
    const centerX = size / 2;
    const centerY = size / 2;
    const radius = size / 3;
    
    // 円の部分（上部）
    path.addOval(Rect.fromCircle(center: Offset(centerX, centerY - 12), radius: radius));
    
    // 三角形の部分（下部のポイント）
    path.moveTo(centerX - radius * 0.6, centerY + radius * 0.2);
    path.lineTo(centerX, centerY + radius * 1.3);
    path.lineTo(centerX + radius * 0.6, centerY + radius * 0.2);
    path.close();
    
    // 影を描画
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, shadowPaint);
    
    // ピンの本体を描画
    canvas.drawPath(path, paint);
    
    // 白い縁取り
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, strokePaint);
    
    // 内側の小さな円（アクセント）
    final innerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(centerX, centerY - 12), 
      radius * 0.4, 
      innerPaint,
    );
    
    final img = await pictureRecorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case '居酒屋':
        return const Color(0xFFFF7043); // 鮮やかなオレンジ
      case 'カフェ・スイーツ':
        return const Color(0xFFFFEB3B); // 鮮やかな黄色
      case '和食':
        return const Color(0xFF4CAF50); // 鮮やかな緑
      case 'イタリアン・フレンチ':
        return const Color(0xFF2196F3); // 鮮やかな青
      case '焼肉・ホルモン':
        return const Color(0xFFE53935); // 鮮やかな赤
      case '中華':
        return const Color(0xFF9C27B0); // 紫
      case 'アジア・エスニック':
        return const Color(0xFF00BCD4); // シアン
      case 'バー・お酒':
        return const Color(0xFF795548); // 茶色
      case 'ファストフード':
        return const Color(0xFFFFC107); // アンバー
      case 'その他グルメ':
        return const Color(0xFF607D8B); // ブルーグレー
      default:
        return const Color(0xFF9E9E9E); // グレー
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _restaurantGroupsSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // レストラン募集グループの読み込み
  void _loadRestaurantGroups() {
    print('🔍 レストラン募集グループの読み込み開始');
    _restaurantGroupsSubscription = _groupService.getRestaurantMeetupGroups().listen((groups) {
      print('🔍 受信したグループ数: ${groups.length}');
      
      setState(() {
        _restaurantGroups = groups;
      });
      _updateMarkersWithGroups();
      // 現在地があれば交通時間計算を実行
      if (_currentPosition != null) {
        _calculateTransitTimes();
      } else {
        print('⚠️ 現在地未取得のため交通時間計算を延期');
      }
    });
  }

  // 所要時間の計算（徒歩+電車+乗り換え込み）
  void _calculateTransitTimes() async {
    if (_currentPosition == null || _restaurantGroups.isEmpty) {
      print('⚠️ 交通時間計算スキップ: 現在地=${_currentPosition != null}, グループ数=${_restaurantGroups.length}');
      return;
    }
    
    print('🔍 交通時間計算開始: 現在地=${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    
    final destinations = _restaurantGroups
        .where((group) => group.restaurantInfo != null)
        .map((group) => {
          'id': group.id,
          'lat': group.restaurantInfo!['latitude'] as double,
          'lng': group.restaurantInfo!['longitude'] as double,
        })
        .toList();
    
    if (destinations.isNotEmpty) {
      for (final dest in destinations) {
        final lat = dest['lat'] as double;
        final lng = dest['lng'] as double;
        
        // 距離を計算
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          lat,
          lng,
        ) / 1000; // km単位
        
        // 徒歩+電車+乗り換え込みの所要時間推定
        final estimatedTime = _transitTimeService.estimateTransitTime(distance);
        
        print('📍 交通時間計算完了: ${dest['id']} → ${estimatedTime}（距離: ${distance.toStringAsFixed(2)}km）');
        
        setState(() {
          _transitTimes[dest['id'] as String] = estimatedTime;
        });
      }
    }
  }

  // レストラン募集グループのマーカーを追加
  void _updateMarkersWithGroups() async {
    print('🔍 マーカー更新開始: 既存マーカー数=${_markers.length}, グループ数=${_restaurantGroups.length}');
    
    // 既存のレストランマーカーを保持（グループマーカーは除外）
    final Set<Marker> restaurantMarkers = _markers
        .where((marker) => marker.markerId.value.startsWith('restaurant_'))
        .toSet();
    
    final Set<Marker> allMarkers = Set<Marker>.from(restaurantMarkers);
    
    // レストラン募集グループのマーカーを追加
    for (final group in _restaurantGroups) {
      if (group.restaurantInfo != null) {
        final restaurantInfo = group.restaurantInfo!;
        final lat = restaurantInfo['latitude'] as double?;
        final lng = restaurantInfo['longitude'] as double?;
        
        if (lat != null && lng != null) {
          final markerId = 'group_${group.id}';
          print('🔍 グループマーカーアイコン生成開始: ${markerId}');
          
          try {
            final icon = await _getGroupMarkerIcon();
            print('✅ グループマーカーアイコン生成成功: ${markerId}');
            
            final marker = Marker(
              markerId: MarkerId(markerId),
              position: LatLng(lat, lng),
              icon: icon,
              infoWindow: InfoWindow(
                title: '募集中: ${restaurantInfo['name']}',
                snippet: _transitTimes[group.id] != null 
                    ? '所要時間: ${_transitTimes[group.id]}'
                    : '募集中のレストラン',
              ),
              onTap: () => _showGroupDetail(group),
              zIndex: 2000.0, // レストランマーカーより確実に前面に表示
            );
            allMarkers.add(marker);
            print('✅ グループマーカーを追加: ${markerId} at ${lat}, ${lng}');
          } catch (e) {
            print('❌ グループマーカーアイコン生成エラー: ${markerId}, $e');
          }
        }
      }
    }
    
    print('🔍 最終マーカー数: ${allMarkers.length} (レストラン:${restaurantMarkers.length}, グループ:${_restaurantGroups.length})');
    
    setState(() {
      _markers = allMarkers;
    });
  }

  // 募集グループ用のマーカーアイコン作成（光沢エフェクトを削除）
  Future<BitmapDescriptor> _getGroupMarkerIcon() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    const double radius = 60.0;
    const double canvasSize = radius * 2.5;
    
    // 透明な背景を使用
    final backgroundPaint = Paint()
      ..color = Colors.transparent
      ..style = PaintingStyle.fill;
    
    // 透明な背景を描画
    canvas.drawRect(Rect.fromLTWH(0, 0, canvasSize, canvasSize), backgroundPaint);
    
    final centerOffset = Offset(canvasSize / 2, canvasSize / 2);
    
    // 外側の影を描画
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(centerOffset.dx + 3, centerOffset.dy + 3), radius, shadowPaint);
    
    // シンプルなグラデーション効果
    final gradientPaint = Paint()
      ..shader = ui.Gradient.radial(
        centerOffset,
        radius,
        [
          const Color(0xFFFF1744), // 鮮やかな赤
          const Color(0xFFD32F2F), // 少し暗い赤
        ],
        [0.0, 1.0],
      );
    
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(centerOffset, radius, strokePaint);
    
    // 内側の円（グラデーション背景）
    canvas.drawCircle(centerOffset, radius - 3, gradientPaint);
    
    // 中央に「募」の文字
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '募',
        style: TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(2, 2),
              blurRadius: 4,
              color: Colors.black54,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        centerOffset.dx - textPainter.width / 2,
        centerOffset.dy - textPainter.height / 2,
      ),
    );
    
    // 光沢エフェクトを削除してシンプルに
    
    final img = await pictureRecorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // グループ詳細表示
  void _showGroupDetail(Group group) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ハンドル
            Center(
              child: Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // グループ名
            Text(
              group.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // レストラン情報
            if (group.restaurantInfo != null) ...[
              Row(
                children: [
                  Icon(Icons.restaurant, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.restaurantInfo!['name'] ?? 'レストラン',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
                             // 所要時間表示
               if (_transitTimes[group.id] != null) ...[
                 Row(
                   children: [
                     Icon(Icons.directions_transit, color: Colors.blue[600]),
                     const SizedBox(width: 8),
                     Text(
                       '所要時間 ${_transitTimes[group.id]}',
                       style: TextStyle(
                         fontSize: 14,
                         color: Colors.blue[700],
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 8),
               ] else ...[
                 Row(
                   children: [
                     Icon(Icons.directions_transit, color: Colors.grey[600]),
                     const SizedBox(width: 8),
                     Text(
                       '所要時間計算中...',
                       style: TextStyle(
                         fontSize: 14,
                         color: Colors.grey[700],
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 8),
               ],
              
              // 開催日時
              if (group.eventDateTime != null) ...[
                Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    Text(
                      '開催: ${_formatEventDateTimeRange(group.eventDateTime!, group.eventEndDateTime)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              
              // 参加人数
              Row(
                children: [
                  Icon(Icons.people, color: Colors.purple[600]),
                  const SizedBox(width: 8),
                  Text(
                    '参加者: ${group.members.length}人',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 20),
            
            // 作成者プロフィール
            _buildCreatorProfile(group),
            
            const SizedBox(height: 20),
            
            // 参加ボタン / グループを見るボタン
            SizedBox(
              width: double.infinity,
              child: _buildGroupActionButton(group),
            ),
          ],
        ),
      ),
    );
  }

  // 日時フォーマット（データベースの日時をそのまま使用）
  String _formatEventDateTime(DateTime dateTime) {
    // データベースから取得した日時はそのまま使用（追加の変換なし）
    print('🕐 日時変換デバッグ: 元の日時=$dateTime (isUtc: ${dateTime.isUtc}) → そのまま使用');
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    
    if (eventDate == today) {
      return '今日 $hour:$minute';
    } else if (eventDate == today.add(const Duration(days: 1))) {
      return '明日 $hour:$minute';
    } else if (eventDate.year == now.year) {
      return '$month/$day $hour:$minute';
    } else {
      return '${dateTime.year}/$month/$day $hour:$minute';
    }
  }

  // 日時範囲フォーマット（データベースの日時をそのまま使用）
  String _formatEventDateTimeRange(DateTime startTime, DateTime? endTime) {
    // データベースから取得した日時はそのまま使用（追加の変換なし）
    print('🕐 日時範囲変換デバッグ: 開始時刻=$startTime, 終了時刻=$endTime → そのまま使用');
    
    if (endTime == null) {
      return _formatEventDateTime(startTime);
    }
    
    final startFormatted = _formatEventDateTime(startTime);
    final endHour = endTime.hour.toString().padLeft(2, '0');
    final endMinute = endTime.minute.toString().padLeft(2, '0');
    
    // 同じ日の場合は時刻のみを表示
    if (startTime.year == endTime.year && 
        startTime.month == endTime.month && 
        startTime.day == endTime.day) {
      return '$startFormatted～$endHour:$endMinute';
    } else {
      return '$startFormatted～${_formatEventDateTime(endTime)}';
    }
  }

  // 作成者プロフィール表示
  Widget _buildCreatorProfile(Group group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.blue[600]),
              const SizedBox(width: 8),
              Text(
                '募集者',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>?>(
            future: _getUserProfile(group.createdBy),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('読み込み中...'),
                  ],
                );
              }
              
              if (snapshot.hasError || !snapshot.hasData) {
                return const Row(
                  children: [
                    Icon(Icons.account_circle, size: 40, color: Colors.grey),
                    SizedBox(width: 12),
                    Text('ユーザー情報を取得できませんでした'),
                  ],
                );
              }
              
              final userProfile = snapshot.data!;
              final String name = userProfile['name'] ?? '名前未設定';
              final String? imageUrl = userProfile['image_url'];
              final int age = userProfile['age'] ?? 0;
              final String? bio = userProfile['bio'];
              
              return GestureDetector(
                onTap: () {
                  // プロフィール詳細画面に遷移
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(userId: group.createdBy),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      // プロフィール画像
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: imageUrl != null 
                            ? NetworkImage(imageUrl)
                            : null,
                        child: imageUrl == null 
                            ? const Icon(Icons.person, size: 24)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      // プロフィール情報
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (age > 0) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '($age歳)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (bio != null && bio.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                bio,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // プロフィール表示アイコン
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ユーザープロフィール取得
  Future<Map<String, dynamic>?> _getUserProfile(String userId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getUserProfile');
      final result = await callable.call({'userId': userId});
      
      if (result.data is Map<String, dynamic>) {
        return result.data as Map<String, dynamic>;
      }
      
      return null;
    } catch (e) {
      print('ユーザープロフィール取得エラー: $e');
      return null;
    }
  }

  // グループアクションボタンを構築
  Widget _buildGroupActionButton(Group group) {
    final currentUserId = _groupService.currentUserId;
    
    if (currentUserId == null) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text('ログインが必要です'),
      );
    }
    
    // 開催日時をチェック（期日チェック）
    final now = DateTime.now();
    final eventDateTime = group.eventDateTime;
    final isExpired = eventDateTime != null && eventDateTime.isBefore(now);
    
    // 現在のユーザーがグループの作成者または参加者かどうかを判定
    final isCreator = group.createdBy == currentUserId;
    final isMember = group.members.contains(currentUserId);
    
    if (isExpired && !isCreator && !isMember) {
      // 期日が過ぎており、かつ作成者・参加者でない場合は非表示
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text('募集終了'),
      );
    }
    
    if (isCreator || isMember) {
      // 作成者または参加者の場合は「グループを見る」ボタン
      return ElevatedButton(
        onPressed: () {
          Navigator.pop(context);
          _viewGroup(group);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text('グループを見る'),
      );
    } else {
      // 非参加者の場合は「募集に参加する」ボタン
      return ElevatedButton(
        onPressed: () {
          Navigator.pop(context);
          _joinGroup(group);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text('募集に参加する'),
      );
    }
  }

  // グループを見る
  void _viewGroup(Group group) {
    // GroupChatPageに遷移
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GroupChatPage(group: group),
      ),
    );
  }

  // グループに参加
  void _joinGroup(Group group) async {
    try {
      await _groupService.joinGroup(group.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「${group.name}」に参加しました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('参加に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // レストラン詳細表示（いいね機能付き）
  void _showRestaurantDetail(Restaurant restaurant) {
    final isLiked = _likedRestaurants.contains(restaurant.id);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ハンドル
                Center(
                  child: Container(
                    width: 50,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // レストラン画像（縦:横 = 2:3の比率、1/2サイズ）
                if (restaurant.imageUrl != null)
                  Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.5, // 1/2サイズ
                      child: AspectRatio(
                        aspectRatio: 3 / 2, // 横:縦 = 3:2 の比率
                        child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      restaurant.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.restaurant, size: 40),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // レストラン名
                Text(
                  restaurant.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // カテゴリと価格帯
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        restaurant.displayCategory,
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        restaurant.displayPriceRange,
                        style: TextStyle(
                          color: Colors.green[800],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // 位置情報
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        restaurant.detailedLocation,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                
                if (restaurant.address != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          restaurant.address!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 20),
                
                // アクションボタン
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _toggleRestaurantLike(restaurant.id, isLiked);
                        },
                        icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border),
                        label: Text(isLiked ? 'いいね済み' : 'いいね'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLiked ? Colors.pink : Colors.pink[100],
                          foregroundColor: isLiked ? Colors.white : Colors.pink[800],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showRecruitmentDialog(restaurant);
                        },
                        icon: const Icon(Icons.group_add),
                        label: const Text('募集作成'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[400],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 募集作成ダイアログ
  void _showRecruitmentDialog(Restaurant restaurant) {
    DateTime? selectedDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    int minParticipants = 2;
    int maxParticipants = 4;

    // グループ名を自動生成する関数
    String _generateGroupName(String userName, DateTime date, TimeOfDay startTime, TimeOfDay endTime, String restaurantName) {
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final startHour = startTime.hour.toString().padLeft(2, '0');
      final startMinute = startTime.minute.toString().padLeft(2, '0');
      final endHour = endTime.hour.toString().padLeft(2, '0');
      final endMinute = endTime.minute.toString().padLeft(2, '0');
      
      // レストラン名を20文字で切り詰める
      String truncatedRestaurantName = restaurantName;
      if (restaurantName.length > 20) {
        truncatedRestaurantName = '${restaurantName.substring(0, 20)}...';
      }
      
      return '$userName-$month/$day $startHour:$startMinute-$endHour:$endMinute-$truncatedRestaurantName';
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('募集を作成'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // レストラン名
                    Text(
                      restaurant.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // グループ名の自動生成について説明
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange[600], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'グループ名は「作成者名-日時-レストラン名」の形式で自動生成されます',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 日付選択
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(selectedDate == null 
                          ? '日付を選択' 
                          : '${selectedDate!.month}/${selectedDate!.day}(${_getWeekday(selectedDate!.weekday)})'),
                      onTap: () => _showScrollableDatePicker(context, (newDate) {
                          setDialogState(() {
                          selectedDate = newDate;
                          });
                      }, selectedDate),
                    ),
                    
                    // 時間範囲選択
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(startTime == null || endTime == null
                          ? '時間を選択'
                          : '${startTime!.format(context)} - ${endTime!.format(context)}'),
                      onTap: () => _showScrollableTimePicker(context, (start, end) {
                            setDialogState(() {
                              startTime = start;
                              endTime = end;
                            });
                      }, startTime, endTime),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 人数設定
                    const Text('参加人数', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('最小: '),
                        DropdownButton<int>(
                          value: minParticipants,
                          items: List.generate(8, (i) => i + 2)
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('${value}人'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              minParticipants = value!;
                              if (maxParticipants < minParticipants) {
                                maxParticipants = minParticipants;
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 16),
                        const Text('最大: '),
                        DropdownButton<int>(
                          value: maxParticipants,
                          items: List.generate(8, (i) => i + 2)
                              .where((value) => value >= minParticipants)
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('${value}人'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              maxParticipants = value!;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: selectedDate != null && startTime != null && endTime != null
                      ? () async {
                          Navigator.pop(context);
                          
                          // ユーザー名を取得
                          String userName = 'ユーザー'; // デフォルト値
                          try {
                            final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
                            final result = await callable.call({
                              'firebaseUid': FirebaseAuth.instance.currentUser?.uid,
                            });
                            if (result.data != null && result.data['exists'] == true) {
                              userName = result.data['user']['name'] ?? 'ユーザー';
                            }
                          } catch (e) {
                            print('ユーザー名取得エラー: $e');
                          }
                          
                          // グループ名を自動生成
                          final generatedGroupName = _generateGroupName(
                            userName,
                            selectedDate!,
                            startTime!,
                            endTime!,
                            restaurant.name,
                          );
                          
                          _createGroup(
                            generatedGroupName,
                            restaurant,
                            selectedDate!,
                            startTime!,
                            endTime!,
                            minParticipants,
                            maxParticipants,
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[400],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('募集作成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 実際のグループ作成処理
  Future<void> _createGroup(
    String groupName,
    dynamic restaurant,
    DateTime selectedDate,
    TimeOfDay startTime,
    TimeOfDay endTime,
    int minParticipants,
    int maxParticipants,
  ) async {
    try {
      // 日時をローカル時間として作成（タイムゾーン対応）
      final eventDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        startTime.hour,
        startTime.minute,
      );
      
      final eventEndDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        endTime.hour,
        endTime.minute,
      );
      
      print('🕐 グループ作成日時デバッグ: 開始時刻=$eventDateTime, 終了時刻=$eventEndDateTime');
      print('🕐 isUtc: 開始=${eventDateTime.isUtc}, 終了=${eventEndDateTime.isUtc}');
      
      // レストラン情報を準備
      final restaurantInfo = {
        'id': restaurant.id?.toString() ?? '',
        'name': restaurant.name,
        'imageUrl': restaurant.imageUrl,
        'category': restaurant.category,
        'prefecture': restaurant.prefecture,
        'nearestStation': restaurant.nearestStation,
        'priceRange': restaurant.priceRange,
        'lowPrice': restaurant.lowPrice,
        'highPrice': restaurant.highPrice,
        'latitude': restaurant.latitude,
        'longitude': restaurant.longitude,
      };
      
      // GroupService を使用してグループを作成
      final groupId = await _groupService.createRestaurantGroup(
        name: groupName,
        description: 'レストラン「${restaurant.name}」での食事会',
        restaurantInfo: restaurantInfo,
        eventDateTime: eventDateTime,
        eventEndDateTime: eventEndDateTime,
        minMembers: minParticipants,
        maxMembers: maxParticipants,
      );
      
      // グループ作成成功後に募集グループを再読み込み
      _loadRestaurantGroups();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'グループ「$groupName」を作成しました！\n'
              'レストラン: ${restaurant.name}\n'
              '日時: ${selectedDate.month}/${selectedDate.day} '
              '${startTime.format(context)}-${endTime.format(context)}\n'
              '人数: $minParticipants-$maxParticipants人',
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ グループ作成エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('グループの作成に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 曜日を日本語で取得
  String _getWeekday(int weekday) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return weekdays[weekday - 1];
  }

  // スクロール式日付ピッカーを表示
  void _showScrollableDatePicker(BuildContext context, Function(DateTime) onDateSelected, DateTime? currentDate) {
    DateTime tempDate = currentDate ?? DateTime.now().add(const Duration(days: 1));
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          height: 260, // さらに縮小
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // 上下の余白を調整
          child: Column(
            children: [
              // ハンドル
              Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '日付を選択',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  children: [
                    // 年
                    Expanded(
                      child: Column(
                        children: [
                          const Text('年', style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 40,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (index) {
                                tempDate = DateTime(DateTime.now().year + index, tempDate.month, tempDate.day);
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  final year = DateTime.now().year + index;
                                  return Center(
                                    child: Text(
                                      '$year',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: year == tempDate.year ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 月
                    Expanded(
                      child: Column(
                        children: [
                          const Text('月', style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 40,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (index) {
                                final month = index + 1;
                                final maxDay = DateTime(tempDate.year, month + 1, 0).day;
                                final day = tempDate.day > maxDay ? maxDay : tempDate.day;
                                tempDate = DateTime(tempDate.year, month, day);
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  final month = index + 1;
                                  return Center(
                                    child: Text(
                                      '$month',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: month == tempDate.month ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 日
                    Expanded(
                      child: Column(
                        children: [
                          const Text('日', style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 40,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (index) {
                                tempDate = DateTime(tempDate.year, tempDate.month, index + 1);
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  final day = index + 1;
                                  final maxDay = DateTime(tempDate.year, tempDate.month + 1, 0).day;
                                  if (day > maxDay) return null;
                                  return Center(
                                    child: Text(
                                      '$day',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: day == tempDate.day ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                },
                                childCount: DateTime(tempDate.year, tempDate.month + 1, 0).day,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('キャンセル'),
                    ),
                  ),
                  Expanded(
                                         child: ElevatedButton(
                       onPressed: () {
                         Navigator.pop(context, tempDate);
                       },
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.orange[400],
                         foregroundColor: Colors.white,
                       ),
                       child: const Text('決定'),
                     ),
                   ),
                 ],
               ),
             ],
           ),
         );
       },
     ).then((selectedDateTime) {
       if (selectedDateTime != null) {
         onDateSelected(selectedDateTime);
       }
     });
  }

  // スクロール式時間ピッカーを表示
  void _showScrollableTimePicker(BuildContext context, Function(TimeOfDay, TimeOfDay) onTimeSelected, TimeOfDay? currentStartTime, TimeOfDay? currentEndTime) {
    TimeOfDay tempStartTime = currentStartTime ?? const TimeOfDay(hour: 18, minute: 0);
    TimeOfDay tempEndTime = currentEndTime ?? const TimeOfDay(hour: 20, minute: 0);
    
    // コントローラーを作成して初期位置を設定
    final FixedExtentScrollController startHourController = FixedExtentScrollController(initialItem: tempStartTime.hour);
    final FixedExtentScrollController startMinuteController = FixedExtentScrollController(initialItem: tempStartTime.minute ~/ 15);
    final FixedExtentScrollController endHourController = FixedExtentScrollController(initialItem: tempEndTime.hour);
    final FixedExtentScrollController endMinuteController = FixedExtentScrollController(initialItem: tempEndTime.minute ~/ 15);
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) => Container(
            height: 280, // オーバーフローを防ぐために高さをさらに縮小
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), // 上下の余白をさらに縮小
            child: Column(
              children: [
                // ハンドル
                Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12), // 間隔を20pxから12pxに縮小
                const Text(
                  '時間を選択',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // フォントサイズを20pxから18pxに縮小
                ),
                const SizedBox(height: 12), // 間隔を20pxから12pxに縮小
                Expanded(
                  child: Column(
                    children: [
                      // 開始時間
                      const Text('開始時間', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4), // 間隔を8pxから4pxに縮小
                      SizedBox(
                        height: 50, // 高さを60pxから50pxに縮小
                        child: Row(
                          children: [
                            // 開始時間 - 時
                            Expanded(
                              child: ListWheelScrollView.useDelegate(
                                controller: startHourController,
                                itemExtent: 30,
                                physics: const FixedExtentScrollPhysics(),
                                onSelectedItemChanged: (index) {
                                  setState(() {
                                    tempStartTime = TimeOfDay(hour: index, minute: tempStartTime.minute);
                                  });
                                },
                                childDelegate: ListWheelChildBuilderDelegate(
                                  builder: (context, index) {
                                    return Center(
                                      child: Text(
                                        '${index.toString().padLeft(2, '0')}時',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    );
                                  },
                                  childCount: 24,
                                ),
                              ),
                            ),
                            // 開始時間 - 分
                            Expanded(
                              child: ListWheelScrollView.useDelegate(
                                controller: startMinuteController,
                                itemExtent: 30,
                                physics: const FixedExtentScrollPhysics(),
                                onSelectedItemChanged: (index) {
                                  setState(() {
                                    tempStartTime = TimeOfDay(hour: tempStartTime.hour, minute: index * 15);
                                  });
                                },
                                childDelegate: ListWheelChildBuilderDelegate(
                                  builder: (context, index) {
                                    final minute = index * 15;
                                    return Center(
                                      child: Text(
                                        '${minute.toString().padLeft(2, '0')}分',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    );
                                  },
                                  childCount: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8), // 間隔を16pxから8pxに縮小
                      // 終了時間
                      const Text('終了時間', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4), // 間隔を8pxから4pxに縮小
                      SizedBox(
                        height: 50, // 高さを60pxから50pxに縮小
                        child: Row(
                          children: [
                            // 終了時間 - 時
                            Expanded(
                              child: ListWheelScrollView.useDelegate(
                                controller: endHourController,
                                itemExtent: 30,
                                physics: const FixedExtentScrollPhysics(),
                                onSelectedItemChanged: (index) {
                                  setState(() {
                                    tempEndTime = TimeOfDay(hour: index, minute: tempEndTime.minute);
                                  });
                                },
                                childDelegate: ListWheelChildBuilderDelegate(
                                  builder: (context, index) {
                                    return Center(
                                      child: Text(
                                        '${index.toString().padLeft(2, '0')}時',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    );
                                  },
                                  childCount: 24,
                                ),
                              ),
                            ),
                            // 終了時間 - 分
                            Expanded(
                              child: ListWheelScrollView.useDelegate(
                                controller: endMinuteController,
                                itemExtent: 30,
                                physics: const FixedExtentScrollPhysics(),
                                onSelectedItemChanged: (index) {
                                  setState(() {
                                    tempEndTime = TimeOfDay(hour: tempEndTime.hour, minute: index * 15);
                                  });
                                },
                                childDelegate: ListWheelChildBuilderDelegate(
                                  builder: (context, index) {
                                    final minute = index * 15;
                                    return Center(
                                      child: Text(
                                        '${minute.toString().padLeft(2, '0')}分',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    );
                                  },
                                  childCount: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('キャンセル'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, {'start': tempStartTime, 'end': tempEndTime});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[400],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('決定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
         ).then((result) {
       if (result != null) {
         onTimeSelected(result['start'], result['end']);
       }
     });
  }

  // フィルターダイアログ
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              const Text(
                'フィルター',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              
              const SizedBox(height: 20),
              
              // カテゴリフィルター
              const Text(
                'カテゴリ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _categories.map((category) {
                  return FilterChip(
                    label: Text(category),
                    selected: _selectedCategories.contains(category),
                    onSelected: (selected) {
                      setDialogState(() {
                        if (selected) {
                          _selectedCategories.add(category);
                        } else {
                          _selectedCategories.remove(category);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 20),
              
              // 価格帯フィルター
              const Text(
                '価格帯',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              RangeSlider(
                values: _priceRange,
                min: 500,
                max: 10000,
                divisions: 19,
                labels: RangeLabels(
                  '¥${_priceRange.start.round()}',
                  '¥${_priceRange.end.round()}',
                ),
                onChanged: (RangeValues values) {
                  setDialogState(() {
                    _priceRange = values;
                  });
                },
              ),
              
              const Spacer(),
              
              // アクションボタン
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setDialogState(() {
                          _selectedCategories.clear();
                          _selectedPrefectures.clear();
                          _priceRange = const RangeValues(1000, 5000);
                        });
                      },
                      child: const Text('クリア'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          // フィルター適用
                        });
                        _updateMarkers();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[400],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('適用'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // APIキーエラー表示ウィジェット
  Widget _buildWebNotSupportedWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            const Text(
              '地図機能は現在準備中です',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Web版での地図機能は現在開発中です。\nモバイルアプリ版をご利用ください。',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('戻る'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[400],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            const Text(
              'Google Maps APIキーが設定されていません',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Google Cloud Platformで\nMaps APIキーを作成し、\nアプリに設定してください',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('戻る'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[400],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // いいね状態を取得
  Future<void> _loadUserLikes() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 5));
      
      if (mounted) {
        setState(() {
          _likedRestaurants = Set<String>.from(result.data['likedRestaurants'] ?? []);
        });
      }
    } catch (e) {
      print('🔥 いいね状態取得エラー: $e');
    }
  }

  // レストランいいね機能
  Future<void> _toggleRestaurantLike(String restaurantId, bool currentLikeState) async {
    if (!mounted) return;

    // 楽観的更新
    setState(() {
      if (currentLikeState) {
        _likedRestaurants.remove(restaurantId);
      } else {
        _likedRestaurants.add(restaurantId);
      }
    });

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        currentLikeState ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      
      await callable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 5));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentLikeState ? 'いいねを外しました' : 'いいねしました'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('🔥 いいね操作エラー: $e');
      
      // エラー時は元に戻す
      if (mounted) {
        setState(() {
          if (currentLikeState) {
            _likedRestaurants.add(restaurantId);
          } else {
            _likedRestaurants.remove(restaurantId);
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('いいね操作に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('地図で探す'),
        backgroundColor: Colors.orange[400],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          // Web版では位置情報ボタンを非表示
          if (!kIsWeb)
            IconButton(
              icon: _isLoadingLocation 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location),
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
            ),
        ],
      ),
      body: Stack(
        children: [
          // API キーエラーの場合のみエラーウィジェットを表示
          if (_hasApiKeyError)
            _buildApiKeyErrorWidget()
          else
            GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
                _mapController = controller;
              },
              initialCameraPosition: _initialPosition,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              compassEnabled: true,
              zoomControlsEnabled: false,
              onCameraMove: (position) {
                // デバウンス処理でマーカー更新の頻度を制限
                _debounceTimer?.cancel();
                _debounceTimer = Timer(_debounceDuration, () {
                _updateMarkers();
                });
              },
              onCameraIdle: () {
                // デバウンス処理でデータ読み込みの頻度を制限
                _debounceTimer?.cancel();
                _debounceTimer = Timer(_debounceDuration, () {
                  _loadRestaurants();
                });
              },
            ),
          
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          
          // 表示件数インジケーター
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${_markers.length}件表示中',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 