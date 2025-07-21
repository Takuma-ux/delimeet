import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import '../models/restaurant_model.dart';
import '../models/group_model.dart';
import '../services/group_service.dart';
import '../services/transit_time_service.dart';
import '../services/web_image_helper.dart';
import 'group_chat_page.dart';
import 'profile_view_page.dart';

class WebMapSearchPage extends StatefulWidget {
  const WebMapSearchPage({super.key});

  @override
  State<WebMapSearchPage> createState() => _WebMapSearchPageState();
}

class _WebMapSearchPageState extends State<WebMapSearchPage> {
  List<Restaurant> _restaurants = [];
  List<Group> _groups = [];
  bool _isLoading = true;
  String? _error;
  Position? _currentPosition;
  bool _showGroups = false;
  String _selectedCategory = '';
  final List<String> _categories = ['すべて', '和食', '洋食', '中華', 'イタリアン', 'フレンチ', 'カフェ'];
  
  // 地図用
  String _mapElementId = 'google-map-${DateTime.now().millisecondsSinceEpoch}';
  js.JsObject? _map;
  js.JsObject? _googleMaps;
  List<js.JsObject> _restaurantMarkers = [];
  js.JsObject? _currentLocationMarker;
  bool _mapInitialized = false;
  
  // 地図の画面サイズ（300px）
  static const double _mapHeight = 300.0;

  @override
  void initState() {
    print('[WebMapSearch] initState実行');
    super.initState();
    _initializeGoogleMaps();
    _initializeLocation();
  }
  
  void _initializeGoogleMaps() {
    print('[WebMapSearch] Google Maps JavaScript API初期化開始');
    
    // HTMLにマップ要素を登録
    ui_web.platformViewRegistry.registerViewFactory(
      _mapElementId,
      (int viewId) {
        final mapElement = html.DivElement()
          ..id = _mapElementId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.position = 'relative';
        
        // 少し遅延させてからGoogle Mapsライブラリを読み込む
        Timer(const Duration(milliseconds: 200), () {
          _loadGoogleMapsLibrary(mapElement);
        });
        
        return mapElement;
      },
    );
  }
  
  Future<void> _loadGoogleMapsLibrary(html.DivElement mapElement) async {
    print('[WebMapSearch] Google Maps ライブラリ読み込み開始');
    
    // Google Maps APIが既に読み込まれているかチェック
    if (js.context['google'] != null && 
        js.context['google']['maps'] != null &&
        js.context['google']['maps']['Map'] != null) {
      print('[WebMapSearch] Google Maps API 既に読み込み済み');
      final googleMaps = js.context['google']['maps'];
      _createMap(mapElement, googleMaps);
      return;
    }
    
    // ポーリングで Google Maps API の読み込みを待つ
    int attempts = 0;
    const maxAttempts = 300; // 30秒間
    
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      attempts++;
      
      try {
        // google.maps が利用可能かチェック
        if (js.context['google'] != null && 
            js.context['google']['maps'] != null &&
            js.context['google']['maps']['Map'] != null) {
          
          print('[WebMapSearch] Google Maps API 読み込み完了');
          timer.cancel();
          
          final googleMaps = js.context['google']['maps'];
          _createMap(mapElement, googleMaps);
          
        } else if (attempts >= maxAttempts) {
          print('[WebMapSearch] Google Maps API読み込みタイムアウト');
          timer.cancel();
          _handleMapLoadError();
        }
      } catch (e) {
        print('[WebMapSearch] API チェック中のエラー: $e');
        if (attempts >= maxAttempts) {
          timer.cancel();
          _handleMapLoadError();
        }
      }
    });
  }
  
  void _createMap(html.DivElement mapElement, js.JsObject googleMaps) {
    print('[WebMapSearch] 地図作成開始');
    
    try {
      final lat = _currentPosition?.latitude ?? 35.6809;
      final lng = _currentPosition?.longitude ?? 139.7673;
      
      final mapOptions = js.JsObject.jsify({
        'center': {'lat': lat, 'lng': lng},
        'zoom': 13,
        'mapTypeId': 'roadmap',
        'zoomControl': true,
        'streetViewControl': false,
        'fullscreenControl': false,
        'mapTypeControl': false,
        'scaleControl': true,
      });
      
      // 従来のAPIを優先的に使用（新しいAPIローダーでエラーが発生しているため）
      print('[WebMapSearch] 従来のAPIを使用して地図を作成');
      _createMapWithLegacyAPI(mapElement, mapOptions, googleMaps);
      
    } catch (e) {
      print('[WebMapSearch] 地図作成エラー: $e');
      _handleMapLoadError();
    }
  }
  
  void _createMapWithLegacyAPI(html.DivElement mapElement, js.JsObject mapOptions, js.JsObject googleMaps) {
    try {
      // 従来のAPIでのMapコンストラクタ取得
      dynamic mapConstructor;
      try {
        // まずwindow.google.maps.Mapを試行
        mapConstructor = js.context['google']['maps']['Map'];
        print('[WebMapSearch] 従来API: Mapコンストラクタ取得成功 (window.google.maps.Map)');
      } catch (e) {
        print('[WebMapSearch] window.google.maps.Map取得エラー: $e');
        try {
          // 次にgoogleMapsオブジェクトから取得を試行
          mapConstructor = googleMaps['Map'];
          print('[WebMapSearch] 従来API: Mapコンストラクタ取得成功 (googleMaps.Map)');
        } catch (e2) {
          print('[WebMapSearch] googleMaps.Map取得エラー: $e2');
          throw Exception('Map constructor not found: $e, $e2');
        }
      }
      
      // 地図を作成
      _map = js.JsObject(mapConstructor, [mapElement, mapOptions]);
      _googleMaps = googleMaps;
      
      print('[WebMapSearch] 従来API: 地図作成完了');
      _mapInitialized = true;
      
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
      
      // マーカーを追加
      _addCurrentLocationMarker();
      
      // レストランデータが既に読み込まれている場合はマーカーを追加
      if (_restaurants.isNotEmpty) {
        print('[WebMapSearch] 既存のレストランデータでマーカーを追加: ${_restaurants.length}件');
        _addRestaurantMarkers();
      }
    } catch (e) {
      print('[WebMapSearch] 従来API: 地図作成エラー: $e');
      throw e;
    }
  }
  
  void _createMapWithNewLoader(html.DivElement mapElement, js.JsObject mapOptions, js.JsObject googleMaps) {
    print('[WebMapSearch] 新しいAPIローダーで地図作成開始');
    
    // 新しいAPIローダーでは、直接window.google.maps.Mapを使用
    try {
      // 直接window.google.maps.Mapを使用
      final mapConstructor = js.context['google']['maps']['Map'];
      
      // 地図を作成
      _map = js.JsObject(mapConstructor, [mapElement, mapOptions]);
      _googleMaps = googleMaps;
      
      print('[WebMapSearch] 新しいAPIローダー: 地図作成完了');
      _mapInitialized = true;
      
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
      
      // マーカーを追加
      _addCurrentLocationMarker();
      
      // レストランデータが既に読み込まれている場合はマーカーを追加
      if (_restaurants.isNotEmpty) {
        print('[WebMapSearch] 既存のレストランデータでマーカーを追加: ${_restaurants.length}件');
        _addRestaurantMarkers();
      }
    } catch (e) {
      print('[WebMapSearch] 新しいAPIローダー: 地図作成エラー: $e');
      _handleMapLoadError();
    }
  }
  
  void _handleMapLoadError() {
    print('[WebMapSearch] 地図読み込みエラー');
    if (mounted) {
      setState(() {
        _error = 'Google Mapsの読み込みに失敗しました。';
      });
    }
  }
  
  void _addCurrentLocationMarker() {
    if (_currentPosition == null || _map == null || _googleMaps == null) return;
    
    print('[WebMapSearch] 現在地マーカー追加');
    
    try {
      // 既存の現在地マーカーを削除
      _currentLocationMarker?.callMethod('setMap', [null]);
      
      // 新しいマーカーを作成
      dynamic markerConstructor;
      try {
        markerConstructor = _googleMaps!['Marker'];
        print('[WebMapSearch] Markerコンストラクタ取得成功');
      } catch (e) {
        print('[WebMapSearch] Markerコンストラクタ取得エラー: $e');
        markerConstructor = js.context['google']['maps']['Marker'];
      }
      
      _currentLocationMarker = js.JsObject(markerConstructor);
      
      _currentLocationMarker!.callMethod('setPosition', [js.JsObject.jsify({
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
      })]);
      
      _currentLocationMarker!.callMethod('setMap', [_map]);
      _currentLocationMarker!.callMethod('setTitle', ['現在地']);
      
      // カスタムアイコンを設定（青い円）
      _currentLocationMarker!.callMethod('setIcon', [js.JsObject.jsify({
        'path': js.context['google']['maps']['SymbolPath']['CIRCLE'],
        'scale': 12,
        'fillColor': '#4285F4',
        'fillOpacity': 1,
        'strokeColor': '#ffffff',
        'strokeWeight': 3,
      })]);
      
      print('[WebMapSearch] 現在地マーカー追加完了');
    } catch (e) {
      print('[WebMapSearch] 現在地マーカー追加エラー: $e');
    }
  }
  
  void _addRestaurantMarkers() {
    if (_map == null || _googleMaps == null) return;
    
    print('[WebMapSearch] レストランマーカー追加開始: ${_restaurants.length}件');
    
    try {
      // 既存のマーカーを削除
      for (final marker in _restaurantMarkers) {
        marker.callMethod('setMap', [null]);
      }
      _restaurantMarkers.clear();
      
      dynamic markerConstructor;
      try {
        markerConstructor = _googleMaps!['Marker'];
        print('[WebMapSearch] レストランマーカー: Markerコンストラクタ取得成功');
      } catch (e) {
        print('[WebMapSearch] レストランマーカー: Markerコンストラクタ取得エラー: $e');
        markerConstructor = js.context['google']['maps']['Marker'];
      }
      
      // 新しいマーカーを追加（最大50件）
      for (int i = 0; i < _restaurants.length && i < 50; i++) {
        final restaurant = _restaurants[i];
        
        if (restaurant.latitude != null && restaurant.longitude != null) {
          final marker = js.JsObject(markerConstructor);
          
          marker.callMethod('setPosition', [js.JsObject.jsify({
            'lat': restaurant.latitude!,
            'lng': restaurant.longitude!,
          })]);
          
          marker.callMethod('setMap', [_map]);
          marker.callMethod('setTitle', [restaurant.name]);
          
          // カスタムアイコンを設定（赤い円）
          marker.callMethod('setIcon', [js.JsObject.jsify({
            'path': js.context['google']['maps']['SymbolPath']['CIRCLE'],
            'scale': 8,
            'fillColor': '#FF5722',
            'fillOpacity': 1,
            'strokeColor': '#ffffff',
            'strokeWeight': 2,
          })]);
          
          // クリックイベントを追加
          try {
            js.context['google']['maps']['event'].callMethod('addListener', [
              marker,
              'click',
              js.allowInterop(() {
                print('[WebMapSearch] レストランマーカークリック: ${restaurant.name}');
                _showRestaurantActionDialog(restaurant);
              })
            ]);
          } catch (e) {
            print('[WebMapSearch] マーカークリックイベント追加エラー: $e');
          }
          
          _restaurantMarkers.add(marker);
        }
      }
      
      print('[WebMapSearch] レストランマーカー追加完了: ${_restaurantMarkers.length}件');
    } catch (e) {
      print('[WebMapSearch] レストランマーカー追加エラー: $e');
    }
  }

  Future<void> _initializeLocation() async {
    print('[WebMapSearch] 位置情報の初期化を開始');
    try {
      // Web版では位置情報取得を制限時間付きで実行
      Position? position;
      
      try {
        print('[WebMapSearch] 現在地取得を試行中...');
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 10));
        print('[WebMapSearch] 現在地取得成功: ${position.latitude}, ${position.longitude}');
      } catch (locationError) {
        print('[WebMapSearch] 現在地取得失敗: $locationError');
        // 位置情報取得に失敗した場合はデフォルト位置（東京駅）を使用
        position = Position(
          latitude: 35.6809,
          longitude: 139.7673,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        print('[WebMapSearch] デフォルト位置を使用: ${position.latitude}, ${position.longitude}');
      }
      
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
        });
        print('[WebMapSearch] 位置情報を設定完了');

        // 地図を更新
        _updateMap();

        // レストラン検索
        print('[WebMapSearch] レストラン検索を開始');
        await _searchRestaurants();
      }
      
    } catch (e) {
      print('[WebMapSearch] 初期化中にエラー: $e');
      if (mounted) {
        setState(() {
          _error = 'エラーが発生しました。再度お試しください。';
          _isLoading = false;
        });
      }
    }
  }
  
  void _updateMap() {
    print('[WebMapSearch] 地図を更新');
    
    if (_map != null && _currentPosition != null) {
      // 地図の中心を現在地に移動
      _map!.callMethod('setCenter', [js.JsObject.jsify({
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
      })]);
      
      // 現在地マーカーを更新
      _addCurrentLocationMarker();
      
      print('[WebMapSearch] 地図中心を更新: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    } else if (_map == null && _currentPosition != null) {
      // 地図がまだ初期化されていない場合は、少し待ってから再試行
      print('[WebMapSearch] 地図が未初期化、再試行をスケジュール');
      Timer(const Duration(milliseconds: 500), () {
        if (mounted && _map == null) {
          print('[WebMapSearch] 地図の再初期化を試行');
          _initializeGoogleMaps();
        }
      });
    }
  }

  Future<void> _searchRestaurants() async {
    if (_currentPosition == null || !mounted) {
      print('[WebMapSearch] レストラン検索をスキップ: currentPosition=${_currentPosition}, mounted=$mounted');
      return;
    }

    print('[WebMapSearch] レストラン検索を実行中...');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('searchRestaurantsWithCoordinates');
      
      final searchParams = {
        'limit': 100,  // 5km範囲なので件数を増加
        'category': _selectedCategory.isEmpty || _selectedCategory == 'すべて' ? null : _selectedCategory,
        // 現在地周辺約5kmの範囲で検索（±0.045度）
        'minLatitude': (_currentPosition?.latitude ?? 35.6809) - 0.045,
        'maxLatitude': (_currentPosition?.latitude ?? 35.6809) + 0.045,
        'minLongitude': (_currentPosition?.longitude ?? 139.7673) - 0.045,
        'maxLongitude': (_currentPosition?.longitude ?? 139.7673) + 0.045,
      };
      
      print('[WebMapSearch] 検索パラメータ: $searchParams');
      
      final result = await callable.call(searchParams).timeout(const Duration(seconds: 15));

      if (!mounted) {
        print('[WebMapSearch] コンポーネントがアンマウントされているため検索を中止');
        return;
      }

      print('[WebMapSearch] Firebase Functions呼び出し成功');

      if (result.data != null && result.data is Map) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(result.data);
        print('[WebMapSearch] レスポンスデータ: ${data.keys}');
        
        final List<dynamic> restaurantData = data['restaurants'] ?? [];
        print('[WebMapSearch] レストランデータ件数: ${restaurantData.length}');
        
        final List<Restaurant> restaurants = [];
        
        for (final item in restaurantData) {
          try {
            if (item != null && item is Map) {
              final restaurantMap = Map<String, dynamic>.from(item);
              final restaurant = Restaurant.fromMap(restaurantMap);
              
              // 現在地からの距離を計算
              if (_currentPosition != null && 
                  restaurant.latitude != null && 
                  restaurant.longitude != null) {
                final distance = Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  restaurant.latitude!,
                  restaurant.longitude!,
                ) / 1000; // km単位
                
                // レストランオブジェクトに距離情報を追加
                restaurantMap['distance'] = distance;
                final restaurantWithDistance = Restaurant.fromMap(restaurantMap);
                restaurants.add(restaurantWithDistance);
              } else {
                restaurants.add(restaurant);
              }
            }
          } catch (e) {
            print('[WebMapSearch] レストランデータの変換エラー: $e');
            // 個別レストランデータのエラーは無視して継続
            continue;
          }
        }
        
        // 距離でソート（近い順）
        if (_currentPosition != null) {
          restaurants.sort((a, b) {
            final aDistance = a.latitude != null && a.longitude != null
                ? Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    a.latitude!,
                    a.longitude!,
                  )
                : double.infinity;
            final bDistance = b.latitude != null && b.longitude != null
                ? Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    b.latitude!,
                    b.longitude!,
                  )
                : double.infinity;
            return aDistance.compareTo(bDistance);
          });
          
          // 最近3件のレストランの距離をログ出力
          print('[WebMapSearch] 最近のレストラン:');
          for (int i = 0; i < restaurants.length && i < 3; i++) {
            final restaurant = restaurants[i];
            if (restaurant.latitude != null && restaurant.longitude != null) {
              final distance = Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                restaurant.latitude!,
                restaurant.longitude!,
              ) / 1000;
              print('[WebMapSearch] ${i + 1}. ${restaurant.name}: ${distance.toStringAsFixed(2)}km');
            }
          }
        }
        
        print('[WebMapSearch] 変換成功したレストラン数: ${restaurants.length}');
        
        setState(() {
          _restaurants = restaurants;
          _isLoading = false;
        });
        
        // JavaScript APIのマーカーを更新
        if (_map != null && _mapInitialized) {
          print('[WebMapSearch] レストラン検索完了後にマーカーを更新');
          _addRestaurantMarkers();
        }
        
        print('[WebMapSearch] レストラン検索完了');
      } else {
        print('[WebMapSearch] 無効なレスポンス形式: ${result.data}');
        setState(() {
          _error = '検索結果の形式が正しくありません';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[WebMapSearch] レストラン検索エラー: $e');
      if (mounted) {
        setState(() {
          _error = 'ネットワークエラーが発生しました。再度お試しください。';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('近くのレストラン'),
        backgroundColor: Colors.pink.shade400,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showGroups ? Icons.restaurant : Icons.group),
            onPressed: () {
              setState(() {
                _showGroups = !_showGroups;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // カテゴリフィルター
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category || 
                    (category == 'すべて' && _selectedCategory.isEmpty);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = selected ? (category == 'すべて' ? '' : category) : '';
                      });
                      _searchRestaurants();
                    },
                    selectedColor: Colors.pink.shade100,
                    checkmarkColor: Colors.pink.shade600,
                  ),
                );
              },
            ),
          ),
          
          // 地図表示
          Container(
            height: _mapHeight,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _error != null && _error!.contains('Google Maps')
                  ? Container(
                      color: Colors.grey.shade100,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              '地図の読み込みに失敗しました',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _error = null;
                                });
                                _initializeGoogleMaps();
                              },
                              child: const Text('再試行'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : HtmlElementView(viewType: _mapElementId),
            ),
          ),
          
          // レストランリスト
          Expanded(
            child: Column(
              children: [
                // レストラン件数表示
                if (_restaurants.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(
                          '${_restaurants.length}件のレストラン（5km圏内）',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // レストランリスト
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 現在地ボタン
          FloatingActionButton(
            onPressed: () {
              if (_currentPosition != null && _map != null) {
                print('[WebMapSearch] 現在地ボタンタップ - 地図を現在地に移動');
                _map!.callMethod('setCenter', [js.JsObject.jsify({
                  'lat': _currentPosition!.latitude,
                  'lng': _currentPosition!.longitude,
                })]);
                _map!.callMethod('setZoom', [15]); // ズームインして詳細表示
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('現在地に移動しました'),
                    duration: Duration(seconds: 1),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('現在地を取得中です...'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            backgroundColor: Colors.blue.shade600,
            child: const Icon(Icons.my_location, color: Colors.white),
            heroTag: "location_btn", // 複数FABのためのタグ
          ),
          const SizedBox(height: 16),
          // リフレッシュボタン
          FloatingActionButton(
            onPressed: _searchRestaurants,
            backgroundColor: Colors.pink.shade400,
            child: const Icon(Icons.refresh, color: Colors.white),
            heroTag: "refresh_btn", // 複数FABのためのタグ
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    print('[WebMapSearch] _buildContent実行: isLoading=$_isLoading, error=$_error, restaurants.length=${_restaurants.length}');
    
    if (_isLoading) {
      print('[WebMapSearch] ローディング状態を表示');
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('検索中...'),
          ],
        ),
      );
    }

    if (_error != null) {
      print('[WebMapSearch] エラー状態を表示: $_error');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _searchRestaurants,
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    if (_restaurants.isEmpty) {
      print('[WebMapSearch] レストランなし状態を表示');
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('近くにレストランが見つかりませんでした'),
          ],
        ),
      );
    }

    print('[WebMapSearch] レストランリストを表示: ${_restaurants.length}件');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _restaurants.length,
      itemBuilder: (context, index) {
        final restaurant = _restaurants[index];
        return _buildRestaurantCard(restaurant);
      },
    );
  }

  Widget _buildRestaurantCard(Restaurant restaurant) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showRestaurantDetails(restaurant),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // レストラン画像
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey.shade200,
                  child: restaurant.imageUrl?.isNotEmpty == true
                      ? WebImageHelper.buildRestaurantImage(
                          restaurant.imageUrl!,
                          width: 80,
                          height: 80,
                        )
                      : Icon(Icons.restaurant, color: Colors.grey.shade400, size: 32),
                ),
              ),
              const SizedBox(width: 16),
              
              // レストラン情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (restaurant.category?.isNotEmpty == true)
                      Text(
                        restaurant.category!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (restaurant.nearestStation?.isNotEmpty == true)
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.nearestStation!,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    // 距離表示を追加
                    if (_currentPosition != null && 
                        restaurant.latitude != null && 
                        restaurant.longitude != null)
                      Row(
                        children: [
                          Icon(Icons.directions_walk, size: 16, color: Colors.blue.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '${(Geolocator.distanceBetween(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                              restaurant.latitude!,
                              restaurant.longitude!,
                            ) / 1000).toStringAsFixed(1)}km',
                            style: TextStyle(
                              color: Colors.blue.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              
              // アクションボタン
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => _showRestaurantDetails(restaurant),
                    color: Colors.pink.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRestaurantDetails(Restaurant restaurant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // レストラン画像
              if (restaurant.imageUrl?.isNotEmpty == true)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      child: WebImageHelper.buildRestaurantImage(
                        restaurant.imageUrl!,
                        width: double.infinity,
                        height: 200,
                      ),
                    ),
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // レストラン情報
              Text(
                restaurant.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (restaurant.category?.isNotEmpty == true)
                Text(
                  restaurant.category!,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              const SizedBox(height: 16),
              
              // 距離情報
              if (_currentPosition != null && 
                  restaurant.latitude != null && 
                  restaurant.longitude != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.directions_walk, color: Colors.blue.shade600),
                      const SizedBox(width: 8),
                      Text(
                        '現在地から${(Geolocator.distanceBetween(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                          restaurant.latitude!,
                          restaurant.longitude!,
                        ) / 1000).toStringAsFixed(1)}km',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // アクションボタン
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showCreateGroupDialog(restaurant);
                      },
                      icon: const Icon(Icons.group_add),
                      label: const Text('募集作成'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
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
  
  // レストランアクション選択ダイアログ
  void _showRestaurantActionDialog(Restaurant restaurant) {
    print('[WebMapSearch] レストランアクション表示: ${restaurant.name}');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ハンドル
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              
              // レストラン情報
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey.shade200,
                      child: restaurant.imageUrl?.isNotEmpty == true
                          ? WebImageHelper.buildRestaurantImage(
                              restaurant.imageUrl!,
                              width: 60,
                              height: 60,
                            )
                          : Icon(Icons.restaurant, color: Colors.grey.shade400, size: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (restaurant.category?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(
                            restaurant.category!,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        if (_currentPosition != null && 
                            restaurant.latitude != null && 
                            restaurant.longitude != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.directions_walk, size: 14, color: Colors.blue.shade500),
                              const SizedBox(width: 4),
                              Text(
                                '${(Geolocator.distanceBetween(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                  restaurant.latitude!,
                                  restaurant.longitude!,
                                ) / 1000).toStringAsFixed(1)}km',
                                style: TextStyle(
                                  color: Colors.blue.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // アクションボタン
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showRestaurantDetails(restaurant);
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('詳細を見る'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showCreateGroupDialog(restaurant);
                      },
                      icon: const Icon(Icons.group_add),
                      label: const Text('募集作成'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
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
  
  // 募集作成ダイアログ
  void _showCreateGroupDialog(Restaurant restaurant) {
    print('[WebMapSearch] 募集作成ダイアログ表示: ${restaurant.name}');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.6,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // タイトル
              Text(
                '${restaurant.name}で募集作成',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 募集タイプ選択
                      const Text(
                        '募集タイプ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // デートリクエスト
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.pink.shade100,
                            child: Icon(Icons.favorite, color: Colors.pink.shade600),
                          ),
                          title: const Text('デートリクエスト'),
                          subtitle: const Text('1対1のデートを募集'),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {
                            Navigator.pop(context);
                            _createDateRequest(restaurant);
                          },
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // グループ募集
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: Icon(Icons.group, color: Colors.orange.shade600),
                          ),
                          title: const Text('グループ募集'),
                          subtitle: const Text('複数人でのグループを募集'),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {
                            Navigator.pop(context);
                            _createGroupMeetup(restaurant);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // デートリクエスト作成
  void _createDateRequest(Restaurant restaurant) {
    print('[WebMapSearch] デートリクエスト作成: ${restaurant.name}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${restaurant.name}でのデートリクエスト作成機能は準備中です'),
        backgroundColor: Colors.pink.shade400,
      ),
    );
  }
  
  // グループ募集作成
  void _createGroupMeetup(Restaurant restaurant) {
    print('[WebMapSearch] グループ募集作成: ${restaurant.name}');
    
    // グループ名を自動生成
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final month = tomorrow.month.toString().padLeft(2, '0');
    final day = tomorrow.day.toString().padLeft(2, '0');
    final groupName = 'グループ-$month/$day-${restaurant.name}';
    
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
    
    // グループ作成処理
    _createGroupWithRestaurant(groupName, restaurantInfo);
  }
  
  // レストラン情報付きグループ作成
  void _createGroupWithRestaurant(String groupName, Map<String, dynamic> restaurantInfo) async {
    try {
      // デフォルトの日時を設定（明日の18:00-20:00）
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final eventDateTime = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0);
      final eventEndDateTime = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 0);
      
      print('[WebMapSearch] グループ作成開始: $groupName');
      
      // Firebase Functionsを使用してグループを作成
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('createRestaurantGroup');
      
      final result = await callable.call({
        'name': groupName,
        'description': 'レストラン「${restaurantInfo['name']}」での食事会',
        'restaurantInfo': restaurantInfo,
        'eventDateTime': eventDateTime.millisecondsSinceEpoch,
        'eventEndDateTime': eventEndDateTime.millisecondsSinceEpoch,
        'minMembers': 2,
        'maxMembers': 4,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('グループ「$groupName」を作成しました！'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      print('[WebMapSearch] グループ作成成功: ${result.data}');
      
    } catch (e) {
      print('[WebMapSearch] グループ作成エラー: $e');
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
} 