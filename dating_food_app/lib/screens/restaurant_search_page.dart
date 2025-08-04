import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/web_image_helper.dart';
import '../models/restaurant_model.dart';
import 'restaurant_detail_page.dart';
import 'map_search_page.dart';
// Web版専用のページを条件付きでインポート
import 'web_map_search_page.dart' if (dart.library.io) 'web_map_search_page_stub.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase追加

class RestaurantSearchPage extends StatefulWidget {
  const RestaurantSearchPage({super.key});

  @override
  State<RestaurantSearchPage> createState() => _RestaurantSearchPageState();
}

class _RestaurantSearchPageState extends State<RestaurantSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  
  // LIKE機能を追加
  Set<String> _likedRestaurants = {};
  
  // Supabaseクライアント
  late final SupabaseClient _supabase;
  
  // ページネーション用の変数
  int _currentLimit = 20;
  final int _maxLimit = 50;
  final int _incrementLimit = 10;
  int _totalCount = 0; // 全検索結果件数を追加
  
  // フィルター用の変数（複数選択対応）
  List<String> _selectedPrefectures = [];
  List<String> _selectedCities = [];
  List<String> _selectedCategories = [];
  List<String> _selectedStations = [];
  
  // 市町村データのキャッシュ
  Map<String, List<Map<String, dynamic>>> _citiesByPrefecture = {};
  
  // 価格帯用の変数（上限・下限）
  int? _minPrice;
  int? _maxPrice;
  
  // フィルター表示状態
  bool _isFilterExpanded = false;
  
  // 固定フィルターオプション
  static const List<String> _prefectures = [
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
    '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
    '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県',
    '三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県',
    '鳥取県', '島根県', '岡山県', '広島県', '山口県',
    '徳島県', '香川県', '愛媛県', '高知県',
    '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
  ];

  static const List<String> _categories = [
    '居酒屋', 'カラオケ・パーティ', 'バー・カクテル', 'ラーメン', '和食', '韓国料理',
    'カフェ・スイーツ', '焼肉・ホルモン', 'アジア・エスニック料理', '洋食', '中華',
    'ダイニングバー・バル', 'イタリアン・フレンチ', 'その他グルメ', 'お好み焼き・もんじゃ',
    '各国料理', '創作料理',
  ];

  // 価格オプション（下限用：1の位が1、上限用：1の位が0）
  static const List<int> _priceOptionsMin = [
    501, 1001, 1501, 2001, 2501, 3001, 3501, 4001, 4501, 5001,
    5501, 6001, 6501, 7001, 7501, 8001, 8501, 9001, 9501, 10001,
    10501, 11001, 11501, 12001, 12501, 13001, 13501, 14001, 14501, 15001,
    16001, 17001, 18001, 19001, 20001, 25001, 30001,
  ];
  
  static const List<int> _priceOptionsMax = [
    1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500,
    6000, 6500, 7000, 7500, 8000, 8500, 9000, 9500, 10000, 10500,
    11000, 11500, 12000, 12500, 13000, 13500, 14000, 14500, 15000, 16000,
    17000, 18000, 19000, 20000, 25000, 30000, 35000,
  ];

  static const Map<String, List<String>> _stationsByPrefecture = {
    '東京都': [
      '東京駅', '新宿駅', '渋谷駅', '池袋駅', '品川駅', '上野駅', '秋葉原駅', '有楽町駅',
      '恵比寿駅', '中目黒駅', '六本木駅', '表参道駅', '原宿駅', '浅草駅', '吉祥寺駅',
      '中野駅', '立川駅', '町田駅', '大崎駅', '五反田駅', '田町駅', '浜松町駅', '神田駅',
      '御茶ノ水駅', '四ツ谷駅', '市ヶ谷駅', '新橋駅', '巣鴨駅', '錦糸町駅', '亀戸駅',
      '北千住駅', '赤羽駅', '大井町駅', '武蔵小杉駅', '蒲田駅', '自由が丘駅', '高円寺駅',
      '八王子駅', '大手町駅', '明大前駅', '学芸大学駅', '駒澤大学駅',
    ],
    '大阪府': [
      '大阪駅', '梅田駅', 'なんば駅', '心斎橋駅', '天王寺駅', '京橋駅', '新大阪駅',
      '堺筋本町駅', '本町駅', '阿倍野駅', '西中島南方駅', '長堀橋駅', '北浜駅',
      '谷町四丁目駅', '谷町六丁目駅', '堺東駅', '住之江公園駅', '弁天町駅', '大阪港駅',
      '南森町駅',
    ],
    '愛知県': [
      '名古屋駅', '栄駅', '金山駅', '大曽根駅', '今池駅', '千種駅', '本山駅', '藤が丘駅',
      '八事駅', '星ヶ丘駅', '久屋大通駅', '上前津駅', '新栄町駅', '高岳駅', '伏見駅',
    ],
    '福岡県': [
      '博多駅', '天神駅', '中洲川端駅', '薬院駅', '大濠公園駅', '赤坂駅', '唐人町駅',
      '西新駅', '祇園駅', '千早駅', '箱崎駅', '吉塚駅', '高宮駅', '姪浜駅', '博多南駅',
    ],
  };

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    // 並列で初期化処理を実行
    _initializeData();
  }

  // データキャッシュ
  static DateTime? _lastLoadTime;
  static List<String> _cachedPrefectures = [];
  static Set<String> _cachedLikedRestaurants = {};
  static const Duration _cacheValidDuration = Duration(minutes: 3);

  Future<void> _initializeData() async {
    if (!mounted) return;
    
    // キャッシュが有効かチェック
    final now = DateTime.now();
    if (_lastLoadTime != null && 
        now.difference(_lastLoadTime!) < _cacheValidDuration) {
      setState(() {
        _selectedPrefectures = List.from(_cachedPrefectures);
        _likedRestaurants = Set.from(_cachedLikedRestaurants);
      });
      
      // キャッシュがあっても軽く検索実行
      if (_selectedPrefectures.isNotEmpty) {
        print('キャッシュ使用: 都道府県が設定済み - ${_selectedPrefectures.join(', ')}');
        _searchRestaurants();
      } else {
        print('キャッシュ使用: 都道府県未設定 - デフォルト検索を実行');
        // 都道府県が設定されていない場合はデフォルト検索を実行
        _searchDefaultRestaurants();
      }
      return;
    }
    
    try {
      // 軽量な初期化のみ実行（Web版ではタイムアウトを短縮）
      final timeout = const Duration(seconds: 1);
      await _loadUserPrefecture().timeout(timeout);
      
      // 背景でいいね状態を読み込み
      _loadUserLikesInBackground();
      
      // 都道府県が設定されていれば軽く検索実行
      if (_selectedPrefectures.isNotEmpty) {
        print('初期化: 都道府県が設定済み - ${_selectedPrefectures.join(', ')}');
        _searchRestaurants();
      } else {
        print('初期化: 都道府県未設定 - デフォルト検索を実行');
        // 都道府県が設定されていない場合はデフォルト検索を実行
        _searchDefaultRestaurants();
      }
      
      // キャッシュに保存
      _lastLoadTime = DateTime.now();
      _cachedPrefectures = List.from(_selectedPrefectures);
      
    } catch (e) {
      // エラー時はデフォルト検索を実行
      _searchDefaultRestaurants();
    }
  }
  
     // 背景でいいね状態を読み込み
   Future<void> _loadUserLikesInBackground() async {
     try {
       await _loadUserLikes().timeout(const Duration(seconds: 3));
       _cachedLikedRestaurants = Set.from(_likedRestaurants);
     } catch (e) {
     }
   }

   // リフレッシュ時のデータ更新（キャッシュクリア付き）
   Future<void> _refreshData() async {
     
     // キャッシュをクリア
     _lastLoadTime = null;
     _cachedPrefectures.clear();
     _cachedLikedRestaurants.clear();
     
     // データを再取得
     await _searchRestaurants();
   }

  // デフォルト検索を実行（都道府県未設定時）
  Future<void> _searchDefaultRestaurants() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 人気の都道府県から最新のレストランを取得
      final popularPrefectures = ['東京都', '大阪府', '愛知県', '福岡県'];
      
      List<dynamic> allResults = [];
      
      // Web版では取得件数を制限
      final maxPrefectures = 1;
      final limitPerPrefecture = 3;
      
      for (String prefecture in popularPrefectures.take(maxPrefectures)) {
        try {
          final result = await _supabase
            .from('restaurants')
            .select('id, name, category, prefecture, city, address, nearest_station, price_range, low_price, high_price, image_url, hotpepper_url, operating_hours, created_at, location_latitude, location_longitude')
            .eq('prefecture', prefecture)
            .order('created_at', ascending: false)
            .limit(limitPerPrefecture);
          
          allResults.addAll(result);
        } catch (e) {
          // エラーがあっても他の都道府県の検索は続行
        }
      }
      
      // 重複除去
      Map<String, dynamic> uniqueResults = {};
      for (var restaurant in allResults) {
        String id = restaurant['id'] ?? '';
        if (id.isNotEmpty) {
          uniqueResults[id] = restaurant;
        }
      }
      
      List<dynamic> finalResults = uniqueResults.values.toList();
      
      setState(() {
        _searchResults = finalResults;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
    }
  }

  // ユーザーの設定した都道府県を取得して自動選択
  Future<void> _loadUserPrefecture() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('getUserProfile');
      final result = await callable.call();
      
      if (result.data != null && result.data['exists'] == true) {
        final userData = result.data['user'];
        final userPrefecture = userData['prefecture']?.toString();
        
        if (userPrefecture != null && userPrefecture.isNotEmpty && _prefectures.contains(userPrefecture)) {
          setState(() {
            _selectedPrefectures = [userPrefecture];
          });
        }
      }
    } catch (e) {
      // エラーの場合は何も選択しない状態で続行
    }
  }

  // 市町村データを取得する関数
  Future<List<Map<String, dynamic>>> _getCitiesByPrefecture(String prefecture) async {
    // キャッシュから取得
    if (_citiesByPrefecture.containsKey(prefecture)) {
      return _citiesByPrefecture[prefecture]!;
    }

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('getCitiesByPrefecture');
      final result = await callable({'prefecture': prefecture});
      
      
      // 型安全な変換
      List<Map<String, dynamic>> cities = [];
      if (result.data != null && result.data['cities'] != null) {
        final citiesData = result.data['cities'];
        
        if (citiesData is List) {
          for (var cityItem in citiesData) {
            if (cityItem is Map) {
              // Map<Object?, Object?> を Map<String, dynamic> に安全に変換
              Map<String, dynamic> cityMap = {};
              cityItem.forEach((key, value) {
                if (key is String) {
                  cityMap[key] = value;
                }
              });
              cities.add(cityMap);
            }
          }
        }
      }
      
      
      // キャッシュに保存
      _citiesByPrefecture[prefecture] = cities;
      
      return cities;
    } catch (e) {
      return [];
    }
  }

  // 都道府県選択時に市町村データを事前取得
  Future<void> _preloadCitiesForSelectedPrefectures() async {
    for (String prefecture in _selectedPrefectures) {
      if (!_citiesByPrefecture.containsKey(prefecture)) {
        await _getCitiesByPrefecture(prefecture);
      }
    }
  }

  // 最適化された市町村選択ダイアログ
  Future<void> _showCitySelectionDialog() async {
    // ローディングダイアログを表示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('市町村データを読み込み中...'),
            ],
          ),
        );
      },
    );

    try {
      // 選択された都道府県の市町村データを並列取得
      Map<String, List<Map<String, dynamic>>> citiesByPrefecture = {};
      
      // 並列処理で高速化
      List<Future<void>> futures = _selectedPrefectures.map((prefecture) async {
        final cities = await _getCitiesByPrefecture(prefecture);
        if (cities.isNotEmpty) {
          citiesByPrefecture[prefecture] = cities;
        }
      }).toList();
      
      await Future.wait(futures);

      // ローディングダイアログを閉じる
      Navigator.of(context).pop();

      if (citiesByPrefecture.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('選択された都道府県の市町村データがありません')),
        );
        return;
      }

      // 市町村選択ダイアログを表示
      final List<String>? result = await showDialog<List<String>>(
        context: context,
        builder: (BuildContext context) {
          List<String> tempSelection = List.from(_selectedCities);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('市町村を選択'),
                content: Container(
                  width: double.maxFinite,
                  height: 500,
                  child: Column(
                    children: [
                      // 全て選択・クリアボタン
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              setDialogState(() {
                                tempSelection.clear();
                                for (var cities in citiesByPrefecture.values) {
                                  for (var cityData in cities) {
                                    tempSelection.add(cityData['city']);
                                  }
                                }
                              });
                            },
                            child: const Text('全て選択'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              setDialogState(() {
                                tempSelection.clear();
                              });
                            },
                            child: const Text('クリア'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 都道府県別市町村リスト（最適化されたレンダリング）
                      Expanded(
                        child: ListView.builder(
                          itemCount: citiesByPrefecture.length,
                          itemBuilder: (context, index) {
                            final entry = citiesByPrefecture.entries.elementAt(index);
                            final prefecture = entry.key;
                            final cities = entry.value;
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 都道府県ラベル
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    prefecture,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // 市町村リスト（ListView.builderで最適化）
                                ...cities.map((cityData) {
                                  final cityName = cityData['city'] as String;
                                  return CheckboxListTile(
                                    dense: true, // コンパクト表示
                                    title: Text(cityName),
                                    subtitle: cityData['city_kana'] != null 
                                        ? Text(
                                            cityData['city_kana'], 
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600])
                                          )
                                        : null,
                                    value: tempSelection.contains(cityName),
                                    onChanged: (bool? value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          tempSelection.add(cityName);
                                        } else {
                                          tempSelection.remove(cityName);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                                const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: const Text('キャンセル'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () {
                      Navigator.of(context).pop(tempSelection);
                    },
                  ),
                ],
              );
            },
          );
        },
      );

      if (result != null) {
        setState(() {
          _selectedCities = result;
        });
        _searchRestaurants();
      }
    } catch (e) {
      // エラー時はローディングダイアログを閉じる
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('市町村データの取得に失敗しました: $e')),
      );
    }
  }

  Future<void> _searchRestaurants({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _currentLimit = 15; // 取得件数を削減
      });
    }

    // --- ここから分岐 ---
    // 都道府県のみ選択 or フィルター未選択時はSupabaseから直接取得
    if (_selectedPrefectures.length == 1 &&
        _selectedCities.isEmpty &&
        _selectedCategories.isEmpty &&
        _selectedStations.isEmpty &&
        (_minPrice == null && _maxPrice == null) &&
        _searchController.text.isEmpty) {
      try {
        print('Supabase直接取得を実行: ${_selectedPrefectures.first}');
        
        // まず、テーブルにデータが存在するかを確認（簡易版）
        final testResult = await _supabase
          .from('restaurants')
          .select('id')
          .eq('prefecture', _selectedPrefectures.first)
          .limit(1);
        
        print('該当都道府県のレストラン存在確認: ${testResult.length}件');
        
        if (testResult.isEmpty) {
          print('該当都道府県にレストランデータが存在しません');
          setState(() {
            _searchResults = [];
            _isLoading = false;
          });
          return;
        }
        
        final result = await _supabase
          .from('restaurants')
          .select('id, name, category, prefecture, city, address, nearest_station, price_range, low_price, high_price, image_url, hotpepper_url, operating_hours, created_at, location_latitude, location_longitude')
          .eq('prefecture', _selectedPrefectures.first)
          .order('created_at', ascending: false)
          .limit(_currentLimit);
        
        print('Supabase取得結果: ${result.length}件');
        
        setState(() {
          _searchResults = result;
          _isLoading = false;
        });
        return;
      } catch (e) {
        print('Supabase取得エラー: $e');
        setState(() {
          _isLoading = false;
          _searchResults = [];
        });
        
        // エラー時はCloud Functionsでの検索にフォールバック
        print('Cloud Functionsでの検索にフォールバック');
        _searchWithCloudFunctions();
        return;
      }
    }
    // --- ここまで分岐 ---

    // それ以外は従来通りCloud Functionsで検索
    _searchWithCloudFunctions();
  }

  // Cloud Functionsでの検索処理
  Future<void> _searchWithCloudFunctions() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        'searchRestaurants',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 4), // タイムアウト短縮
        ),
      );
      
      List<dynamic> allResults = [];
      
      // 軽量化：最大3都道府県、各3市町村まで制限
      if (_selectedPrefectures.isNotEmpty) {
        final limitedPrefectures = _selectedPrefectures.take(3).toList();
        
        for (String prefecture in limitedPrefectures) {
          // この都道府県に属する選択された市町村を取得（最大3件）
          final selectedCitiesForPrefecture = _selectedCities.where((city) {
            final citiesInPrefecture = _citiesByPrefecture[prefecture] ?? [];
            return citiesInPrefecture.any((cityData) => cityData['city'] == city);
          }).take(3).toList();
          
          if (selectedCitiesForPrefecture.isNotEmpty) {
            // 選択された市町村ごとに個別検索（最大3件）
            for (String city in selectedCitiesForPrefecture) {
              Map<String, dynamic> searchParams = {
                'prefecture': prefecture,
                'city': city,
                'limit': 5, // 各市町村から5件ずつに制限
              };
              
              // キーワード検索を追加
              if (_searchController.text.isNotEmpty) {
                searchParams['keyword'] = _searchController.text;
              }
              
              if (_selectedCategories.isNotEmpty) {
                searchParams['category'] = _selectedCategories;
              }
              if (_selectedStations.isNotEmpty) {
                searchParams['nearestStation'] = _selectedStations.first;
              }
              
              // 価格帯の処理（ハイフン区切り形式で送信）
              if (_minPrice != null || _maxPrice != null) {
                String priceRange = '';
                if (_minPrice != null) priceRange += _minPrice.toString();
                priceRange += '-';
                if (_maxPrice != null) priceRange += _maxPrice.toString();
                searchParams['priceRange'] = priceRange;
              }
              
              try {
                final result = await callable(searchParams);
                if (result.data is Map && result.data['restaurants'] != null) {
                  allResults.addAll(List.from(result.data['restaurants']));
                } else {
                  allResults.addAll(List.from(result.data ?? []));
                }
              } catch (e) {
                // エラーがあっても他の市町村の検索は続行
              }
            }
          } else {
            // 市町村が選択されていない場合は都道府県全体で検索
            Map<String, dynamic> searchParams = {
              'prefecture': prefecture,
              'limit': 8, // 都道府県全体では8件に制限
            };
            
            // キーワード検索を追加
            if (_searchController.text.isNotEmpty) {
              searchParams['keyword'] = _searchController.text;
            }
            
            if (_selectedCategories.isNotEmpty) {
              searchParams['category'] = _selectedCategories;
            }
            if (_selectedStations.isNotEmpty) {
              searchParams['nearestStation'] = _selectedStations.first;
            }
            
            // 価格帯の処理（ハイフン区切り形式で送信）
            if (_minPrice != null || _maxPrice != null) {
              String priceRange = '';
              if (_minPrice != null) priceRange += _minPrice.toString();
              priceRange += '-';
              if (_maxPrice != null) priceRange += _maxPrice.toString();
              searchParams['priceRange'] = priceRange;
            }
            
            try {
              final result = await callable(searchParams);
              if (result.data is Map && result.data['restaurants'] != null) {
                allResults.addAll(List.from(result.data['restaurants']));
              } else {
                allResults.addAll(List.from(result.data ?? []));
              }
            } catch (e) {
              // エラーがあっても他の都道府県の検索は続行
            }
          }
        }
      } else {
        // 都道府県未選択の場合は通常検索
        Map<String, dynamic> searchParams = {'limit': _currentLimit};
        
        // キーワード検索を追加
        if (_searchController.text.isNotEmpty) {
          searchParams['keyword'] = _searchController.text;
        }
        
        if (_selectedCategories.isNotEmpty) {
          searchParams['category'] = _selectedCategories;
        }
        if (_selectedStations.isNotEmpty) {
          searchParams['nearestStation'] = _selectedStations.first; // 現在は最初の駅のみ使用
        }
        
        // 価格帯の処理（ハイフン区切り形式で送信）
        if (_minPrice != null || _maxPrice != null) {
          String priceRange = '';
          if (_minPrice != null) priceRange += _minPrice.toString();
          priceRange += '-';
          if (_maxPrice != null) priceRange += _maxPrice.toString();
          searchParams['priceRange'] = priceRange;
        }
        
        final result = await callable(searchParams);
        if (result.data is Map && result.data['restaurants'] != null) {
          allResults = List.from(result.data['restaurants']);
        } else {
          allResults = List.from(result.data ?? []);
        }
      }
      
      // 重複除去（同じIDのレストランを削除）
      Map<String, dynamic> uniqueResults = {};
      for (var restaurant in allResults) {
        String id = restaurant['id'] ?? '';
        if (id.isNotEmpty) {
          uniqueResults[id] = restaurant;
        }
      }
      
      List<dynamic> finalResults = uniqueResults.values.toList();
      
      // レビュー平均得点を取得
      await _loadReviewRatings(finalResults);
      
      setState(() {
        _searchResults = finalResults;
        _isLoading = false;
      });
      
      
    } catch (e) {
      print('Cloud Functions検索エラー: $e');
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
    }
  }

  Future<void> _loadReviewRatings(List<dynamic> restaurants) async {
    try {
      // 各レストランのレビュー平均得点を並列取得
      List<Future<void>> futures = restaurants.map((restaurant) async {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('getRestaurantAverageRating');
          final result = await callable.call({'restaurantId': restaurant['id']});
          
          restaurant['average_rating'] = result.data['averageRating'];
          restaurant['total_reviews'] = result.data['totalReviews'];
        } catch (e) {
          restaurant['average_rating'] = null;
          restaurant['total_reviews'] = 0;
        }
      }).toList();
      
      await Future.wait(futures);
    } catch (e) {
    }
  }

  Future<void> _loadUserLikes() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 3));
      
      if (mounted) {
        setState(() {
          _likedRestaurants = Set<String>.from(result.data['likedRestaurants'] ?? []);
        });
      }
    } catch (e) {
      // エラー時は空の状態を維持
    }
  }

  Future<void> _toggleRestaurantLike(String restaurantId, bool currentLikeState) async {
    if (!mounted) return;

    // 即座にUIを更新（楽観的更新）
    setState(() {
      if (currentLikeState) {
        _likedRestaurants.remove(restaurantId);
      } else {
        _likedRestaurants.add(restaurantId);
      }
    });

    // バックグラウンドでAPI呼び出し
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        currentLikeState ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      
      // タイムアウトを短く設定
      await callable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 5));
      
      // お気に入り追加時は地元案内人バッジの得点を更新
      if (!currentLikeState) {
        try {
          final badgeCallable = FirebaseFunctions.instance.httpsCallable('updateFavoriteRestaurantScore');
          await badgeCallable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 3));
        } catch (e) {
          // バッジ更新エラーはメイン機能に影響しない
        }
      }
      
    } catch (e) {
      
      // エラー時のみUIを元に戻す
      if (mounted) {
        setState(() {
          if (currentLikeState) {
            _likedRestaurants.add(restaurantId);
          } else {
            _likedRestaurants.remove(restaurantId);
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('いいね操作に失敗しました: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // _buildPriceRangeString関数は削除（直接パラメータ構築に変更）

  int _getActiveFilterCount() {
    int count = 0;
    count += _selectedPrefectures.length;
    count += _selectedCities.length;
    count += _selectedCategories.length;
    count += _selectedStations.length;
    if (_minPrice != null || _maxPrice != null) count += 1;
    return count;
  }

  Widget _buildSelectedFilterChip(String type, String value) {
    return Chip(
      label: Text(
        value,
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: const Color(0xFFFDF5E6),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: () => _removeFilter(type, value),
    );
  }

  void _removeFilter(String type, String value) {
    setState(() {
      switch (type) {
        case 'prefecture':
          _selectedPrefectures.remove(value);
          // 都道府県を削除した場合、関連する市町村と駅も削除
          _selectedCities.removeWhere((city) {
            final citiesInPrefecture = _citiesByPrefecture[value] ?? [];
            return citiesInPrefecture.any((cityData) => cityData['city'] == city);
          });
          _selectedStations.removeWhere((station) {
            return _stationsByPrefecture[value]?.contains(station) == true;
          });
          break;
        case 'city':
          _selectedCities.remove(value);
          break;
        case 'category':
          _selectedCategories.remove(value);
          break;
        case 'station':
          _selectedStations.remove(value);
          break;
        case 'price':
          _minPrice = null;
          _maxPrice = null;
          break;
      }
    });
    _searchRestaurants();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('レストラン検索'),
        backgroundColor: const Color(0xFFFDDEA5),
        foregroundColor: Colors.white,
        leading: kIsWeb ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ) : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: '地図で探す',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MapSearchPage(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 検索バー
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'キーワードで検索',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
              ),
              onSubmitted: (_) => _searchRestaurants(),
            ),
          ),

          // フィルターエリア（折りたたみ可能）
          Container(
            color: Colors.grey[50],
            child: Column(
              children: [
                // フィルター切り替えボタン
                InkWell(
                  onTap: () {
                    setState(() {
                      _isFilterExpanded = !_isFilterExpanded;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          _isFilterExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'フィルター',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        // 選択中のフィルター数を表示
                        if (_getActiveFilterCount() > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[600],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_getActiveFilterCount()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                
                // フィルター内容（展開時のみ表示）
                if (_isFilterExpanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // フィルターボタン行
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                // 都道府県フィルター
                FilterChip(
                  label: Text(
                    _selectedPrefectures.isEmpty
                        ? '都道府県'
                        : '${_selectedPrefectures.length}件選択中',
                  ),
                  selected: _selectedPrefectures.isNotEmpty,
                  onSelected: (_) async {
                    final List<String>? result = await showDialog<List<String>>(
                      context: context,
                      builder: (BuildContext context) {
                        List<String> tempSelection = List.from(_selectedPrefectures);
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                            return AlertDialog(
                              title: const Text('都道府県を選択'),
                              content: Container(
                                width: double.maxFinite,
                                height: 400,
                                child: Column(
                                  children: [
                                    // 全て選択・クリアボタン
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        ElevatedButton(
                                          onPressed: () {
                                            setDialogState(() {
                                              tempSelection = List.from(_prefectures);
                                            });
                                          },
                                          child: const Text('全て選択'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            setDialogState(() {
                                              tempSelection.clear();
                                            });
                                          },
                                          child: const Text('クリア'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // 都道府県リスト
                                    Expanded(
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _prefectures.length,
                                        itemBuilder: (context, index) {
                                          final prefecture = _prefectures[index];
                                          return CheckboxListTile(
                                            title: Text(prefecture),
                                            value: tempSelection.contains(prefecture),
                                            onChanged: (bool? value) {
                                              setDialogState(() {
                                                if (value == true) {
                                                  tempSelection.add(prefecture);
                                                } else {
                                                  tempSelection.remove(prefecture);
                                                }
                                              });
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  child: const Text('キャンセル'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                TextButton(
                                  child: const Text('OK'),
                                  onPressed: () {
                                    Navigator.of(context).pop(tempSelection);
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );

                    if (result != null) {
                      setState(() {
                        _selectedPrefectures = result;
                        // 選択された都道府県に含まれない駅を除外
                        _selectedStations.removeWhere((station) {
                          return !result.any((prefecture) =>
                              _stationsByPrefecture[prefecture]?.contains(station) == true);
                        });
                        // 選択された都道府県に含まれない市町村を除外
                        _selectedCities.removeWhere((city) {
                          return !result.any((prefecture) {
                            final citiesInPrefecture = _citiesByPrefecture[prefecture] ?? [];
                            return citiesInPrefecture.any((cityData) => cityData['city'] == city);
                          });
                        });
                      });
                      
                      // 新しく選択された都道府県の市町村データを事前取得（バックグラウンド）
                      _preloadCitiesForSelectedPrefectures();
                      
                      _searchRestaurants();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 市町村フィルター（都道府県が選択されている場合のみ表示）
                if (_selectedPrefectures.isNotEmpty)
                  FilterChip(
                    label: Text(
                      _selectedCities.isEmpty
                          ? '市町村'
                          : '${_selectedCities.length}件選択中',
                    ),
                    selected: _selectedCities.isNotEmpty,
                    onSelected: (_) => _showCitySelectionDialog(),
                  ),
                if (_selectedPrefectures.isNotEmpty)
                  const SizedBox(width: 8),

                // カテゴリーフィルター（複数選択対応）
                FilterChip(
                  label: Text(
                    _selectedCategories.isEmpty
                        ? 'カテゴリー'
                        : '${_selectedCategories.length}件選択中',
                  ),
                  selected: _selectedCategories.isNotEmpty,
                  onSelected: (_) async {
                    final List<String>? result = await showDialog<List<String>>(
                      context: context,
                      builder: (BuildContext context) {
                        List<String> tempSelection = List.from(_selectedCategories);
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                            return AlertDialog(
                              title: const Text('カテゴリーを選択'),
                              content: Container(
                                width: double.maxFinite,
                                height: 400,
                                child: Column(
                                  children: [
                                    // 全て選択・クリアボタン
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        ElevatedButton(
                                          onPressed: () {
                                            setDialogState(() {
                                              tempSelection = List.from(_categories);
                                            });
                                          },
                                          child: const Text('全て選択'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            setDialogState(() {
                                              tempSelection.clear();
                                            });
                                          },
                                          child: const Text('クリア'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // カテゴリリスト
                                    Expanded(
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _categories.length,
                                        itemBuilder: (context, index) {
                                          final category = _categories[index];
                                          return CheckboxListTile(
                                            title: Text(category),
                                            value: tempSelection.contains(category),
                                            onChanged: (bool? value) {
                                              setDialogState(() {
                                                if (value == true) {
                                                  tempSelection.add(category);
                                                } else {
                                                  tempSelection.remove(category);
                                                }
                                              });
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  child: const Text('キャンセル'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                TextButton(
                                  child: const Text('OK'),
                                  onPressed: () {
                                    Navigator.of(context).pop(tempSelection);
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );

                    if (result != null) {
                      setState(() {
                        _selectedCategories = result;
                      });
                      _searchRestaurants();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 駅フィルター（選択した都道府県に駅がある場合のみ表示）
                if (_selectedPrefectures.isNotEmpty && 
                    _selectedPrefectures.any((prefecture) => 
                        _stationsByPrefecture.containsKey(prefecture)))
                  FilterChip(
                    label: Text(
                      _selectedStations.isEmpty
                          ? '最寄り駅'
                          : '${_selectedStations.length}駅選択中',
                    ),
                    selected: _selectedStations.isNotEmpty,
                    onSelected: (_) async {
                      // 都道府県別に駅を整理
                      Map<String, List<String>> stationsByPrefecture = {};
                      for (String prefecture in _selectedPrefectures) {
                        if (_stationsByPrefecture.containsKey(prefecture)) {
                          stationsByPrefecture[prefecture] = _stationsByPrefecture[prefecture]!;
                        }
                      }
                      
                      final List<String>? result = await showDialog<List<String>>(
                        context: context,
                        builder: (BuildContext context) {
                          List<String> tempSelection = List.from(_selectedStations);
                          
                          return StatefulBuilder(
                            builder: (context, setDialogState) {
                              return AlertDialog(
                                title: const Text('最寄り駅を選択'),
                                content: Container(
                                  width: double.maxFinite,
                                  height: 500,
                                  child: Column(
                                    children: [
                                      // 全て選択・クリアボタン
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          ElevatedButton(
                                            onPressed: () {
                                              setDialogState(() {
                                                tempSelection.clear();
                                                for (var stations in stationsByPrefecture.values) {
                                                  tempSelection.addAll(stations);
                                                }
                                              });
                                            },
                                            child: const Text('全て選択'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              setDialogState(() {
                                                tempSelection.clear();
                                              });
                                            },
                                            child: const Text('クリア'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // 都道府県別駅リスト
                                      Expanded(
                                        child: ListView(
                                          children: stationsByPrefecture.entries.map((entry) {
                                            final prefecture = entry.key;
                                            final stations = entry.value;
                                            
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // 都道府県ラベル
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[100],
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    prefecture,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                // 駅リスト
                                                ...stations.map((station) {
                                                  return CheckboxListTile(
                                                    title: Text(station),
                                                    value: tempSelection.contains(station),
                                                    onChanged: (bool? value) {
                                                      setDialogState(() {
                                                        if (value == true) {
                                                          tempSelection.add(station);
                                                        } else {
                                                          tempSelection.remove(station);
                                                        }
                                                      });
                                                    },
                                                  );
                                                }).toList(),
                                                const SizedBox(height: 16),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: const Text('キャンセル'),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  TextButton(
                                    child: const Text('OK'),
                                    onPressed: () {
                                      Navigator.of(context).pop(tempSelection);
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );

                      if (result != null) {
                        setState(() {
                          _selectedStations = result;
                        });
                        _searchRestaurants();
                      }
                    },
                  ),
                const SizedBox(width: 8),

                // 価格帯フィルター
                FilterChip(
                  label: Text(
                    _minPrice == null && _maxPrice == null
                        ? '価格帯'
                        : _maxPrice == null
                            ? '${_minPrice}円〜'
                            : '${_minPrice ?? 0}〜${_maxPrice}円',
                  ),
                  selected: _minPrice != null || _maxPrice != null,
                  onSelected: (_) async {
                    final result = await showDialog<Map<String, int?>>(
                      context: context,
                      builder: (BuildContext context) {
                        int? tempMin = _minPrice;
                        int? tempMax = _maxPrice;
                        return StatefulBuilder(
                          builder: (BuildContext context, StateSetter setDialogState) {
                            return AlertDialog(
                          title: const Text('価格帯を選択'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Text('下限: '),
                                  Expanded(
                                    child: DropdownButton<int>(
                                      value: tempMin,
                                      hint: const Text('選択してください'),
                                      isExpanded: true,
                                      items: [
                                        const DropdownMenuItem<int>(
                                          value: null,
                                          child: Text('指定なし'),
                                        ),
                                        ..._priceOptionsMin.where((price) {
                                          // 上限が設定されている場合、上限より小さい価格のみ表示
                                          return tempMax == null || price < tempMax!;
                                        }).map((price) {
                                          return DropdownMenuItem<int>(
                                            value: price,
                                            child: Text('${price}円'),
                                          );
                                        }),
                                      ],
                                      onChanged: (int? value) {
                                        setDialogState(() {
                                          tempMin = value;
                                          // 下限が上限より大きい場合、上限をクリア
                                          if (value != null && tempMax != null && value > tempMax!) {
                                            tempMax = null;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Text('上限: '),
                                  Expanded(
                                    child: DropdownButton<int>(
                                      value: tempMax,
                                      hint: const Text('選択してください'),
                                      isExpanded: true,
                                      items: [
                                        const DropdownMenuItem<int>(
                                          value: null,
                                          child: Text('指定なし'),
                                        ),
                                        ..._priceOptionsMax.where((price) {
                                          // 下限が設定されている場合、下限より大きい価格のみ表示
                                          return tempMin == null || price > tempMin!;
                                        }).map((price) {
                                          return DropdownMenuItem<int>(
                                            value: price,
                                            child: Text('${price}円'),
                                          );
                                        }),
                                      ],
                                      onChanged: (int? value) {
                                        setDialogState(() {
                                          tempMax = value;
                                          // 上限が下限より小さい場合、下限をクリア
                                          if (value != null && tempMin != null && value < tempMin!) {
                                            tempMin = null;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                              actions: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        child: const Text('クリア'),
                                        onPressed: () {
                                          setDialogState(() {
                                            tempMin = null;
                                            tempMax = null;
                                          });
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton(
                                        child: const Text('キャンセル'),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton(
                                        child: const Text('OK'),
                                        onPressed: () {
                                          // バリデーション：下限が上限を上回っていないかチェック
                                          if (tempMin != null && tempMax != null && tempMin! > tempMax!) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('下限が上限を上回っています。'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                            return;
                                          }
                                          Navigator.of(context)
                                              .pop({'min': tempMin, 'max': tempMax});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );

                    if (result != null) {
                      setState(() {
                        _minPrice = result['min'];
                        _maxPrice = result['max'];
                      });
                      _searchRestaurants();
                    }
                  },
                ),
                            ],
                          ),
                        ),
                        
                        // 選択されたフィルターの表示
                        if (_getActiveFilterCount() > 0) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ..._selectedPrefectures.map((value) =>
                                  _buildSelectedFilterChip('prefecture', value)),
                              ..._selectedCities.map((value) =>
                                  _buildSelectedFilterChip('city', value)),
                              ..._selectedCategories.map((value) =>
                                  _buildSelectedFilterChip('category', value)),
                              ..._selectedStations.map((value) =>
                                  _buildSelectedFilterChip('station', value)),
                              if (_minPrice != null || _maxPrice != null)
                                _buildSelectedFilterChip('price', 
                                  _minPrice != null && _maxPrice != null 
                                    ? '${_minPrice}円〜${_maxPrice}円'
                                    : _minPrice != null 
                                      ? '${_minPrice}円〜'
                                      : '〜${_maxPrice}円'
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 検索結果
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedPrefectures.isEmpty 
                                    ? '人気のレストランを読み込み中...\nしばらくお待ちください。'
                                    : '検索結果がありません。\n条件を変更して再度お試しください。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                                if (_selectedPrefectures.isEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    '都道府県を選択すると、\nより詳細な検索ができます。',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _searchResults.length) {
                                // もっと見るボタン
                                if (_searchResults.length >= _currentLimit &&
                                    _currentLimit < _maxLimit) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final newLimit =
                                            _currentLimit + _incrementLimit;
                                        setState(() {
                                          _currentLimit = newLimit > _maxLimit
                                              ? _maxLimit
                                              : newLimit;
                                        });
                                        _searchRestaurants(loadMore: true);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey[600],
                                        minimumSize:
                                            const Size(double.infinity, 50),
                                      ),
                                      child: const Text('もっと見る'),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              }

                              final restaurant = _searchResults[index];
                              final restaurantId = restaurant['id'] as String;
                              final isLiked =
                                  _likedRestaurants.contains(restaurantId);

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    // レストラン詳細画面への遷移
                                    final restaurantModel = Restaurant(
                                      id: restaurant['id'],
                                      name: restaurant['name'] ?? '',
                                      category: restaurant['category'],
                                      prefecture: restaurant['prefecture'],
                                      city: restaurant['city'],
                                      address: restaurant['address'],
                                      nearestStation: restaurant['nearest_station'],
                                      priceRange: restaurant['price_range'],
                                      lowPrice: restaurant['low_price'],
                                      highPrice: restaurant['high_price'],
                                      imageUrl: restaurant['image_url'],
                                      photoUrl: restaurant['photo_url'],
                                      priceLevel: restaurant['price_level'],
                                      operatingHours: restaurant['operating_hours'],
                                      hotpepperUrl: restaurant['hotpepper_url'],
                                      latitude: restaurant['latitude'],
                                      longitude: restaurant['longitude'],
                                    );
                                    
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => RestaurantDetailPage(
                                          restaurant: restaurantModel,
                                        ),
                                      ),
                                    );
                                  },
                                  child: SizedBox(
                                    height: 121, // カードの高さを3px大きく調整
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 左側の画像
                                        (() {
                                          final imageUrl = restaurant['photo_url'] ?? restaurant['image_url'];
                                          return WebImageHelper.buildRestaurantImage(
                                            imageUrl,
                                            width: 121,
                                            height: 121,
                                            borderRadius: const BorderRadius.horizontal(
                                              left: Radius.circular(16),
                                            ),
                                          );
                                        })(),
                                                                // 右側の情報
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // タイトル部分（固定の高さ）
                                SizedBox(
                                  height: 38, // 2行分の高さを固定
                                  child: Text(
                                    restaurant['name']?.toString() ?? 'レストラン名未設定',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // 詳細情報とボタンを横並び（残りの高さを使用）
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 左側：詳細情報（カテゴリ・都道府県・最寄駅・料金）
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: [
                                            // カテゴリ
                                            Text(
                                              restaurant['category']?.toString() ?? 'カテゴリなし',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 3),
                                            // 都道府県と駅を横並び
                                            Row(
                                              children: [
                                                // 都道府県
                                                if (restaurant['prefecture'] != null) ...[
                                                  Icon(
                                                    Icons.location_on,
                                                    size: 10,
                                                    color: Colors.grey[500],
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    restaurant['prefecture'].toString(),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                                // スペーサー
                                                if (restaurant['prefecture'] != null && restaurant['nearest_station'] != null)
                                                  const SizedBox(width: 8),
                                                // 最寄り駅
                                                if (restaurant['nearest_station'] != null) ...[
                                                  Icon(
                                                    Icons.train,
                                                    size: 10,
                                                    color: Colors.grey[500],
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Flexible(
                                                    child: Text(
                                                      restaurant['nearest_station'].toString(),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey[600],
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            // 価格帯
                                            if (restaurant['price_range'] != null)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.monetization_on,
                                                    size: 10,
                                                    color: Colors.grey[600],
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    restaurant['price_range'].toString(),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey[600],
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 3),
                                            // レビュー平均評価
                                            if (restaurant['average_rating'] != null)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.star,
                                                    size: 10,
                                                    color: Colors.amber,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${restaurant['average_rating'].toStringAsFixed(1)}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.amber[700],
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (restaurant['total_reviews'] != null) ...[
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '(${restaurant['total_reviews']})',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                      // 右側：いいねボタンと三点ボタン
                                      SizedBox(
                                        width: 36,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: [
                                            // いいねボタン
                                            GestureDetector(
                                              onTap: () {
                                                _toggleRestaurantLike(restaurantId, isLiked);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: isLiked ? Colors.grey[600] : Colors.grey[200],
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                                  color: isLiked ? Colors.white : Colors.grey[600],
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // 三点ボタン（メニュー表示）
                                            if (restaurant['hotpepper_url'] != null)
                                              GestureDetector(
                                                onTap: () {
                                                  _showRestaurantMenu(context, restaurant);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Icon(
                                                    Icons.more_horiz,
                                                    color: Colors.grey[600],
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
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
            },
          ),
  ),
),
      ],
    ),
  );
}

// レストランメニューモーダルを表示
void _showRestaurantMenu(BuildContext context, dynamic restaurant) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // レストラン名
            Text(
              restaurant['name']?.toString() ?? 'レストラン名未設定',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // HotPepperボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context); // モーダルを閉じる
                  final url = restaurant['hotpepper_url'].toString();
                  try {
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      throw 'URLを開けませんでした: $url';
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('URLを開けませんでした: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new, color: Colors.white),
                label: const Text(
                  'HotPepperで詳細を見る',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // キャンセルボタン
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'キャンセル',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      );
    },
  );
}

  // Web版用の画像ウィジェット (WebImageHelper使用)
  Widget _buildWebImage(String imageUrl, {required double width, required double height}) {
    return WebImageHelper.buildImage(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }
} 