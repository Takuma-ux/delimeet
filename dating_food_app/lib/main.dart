import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'dart:async';
import 'dart:typed_data';
import 'firebase_options.dart';
import 'screens/auth/login_page.dart';
import 'screens/auth/profile_setup_page.dart';
import 'screens/account_page.dart';
import 'screens/match_list_page.dart';
import 'screens/match_detail_page.dart';
import 'screens/profile_view_page.dart';
import 'screens/user_search_page.dart';
import 'screens/likes_page.dart';
import 'screens/search_page.dart';
import 'screens/restaurant_search_page.dart';
import 'screens/favorite_stores_page.dart';
import 'pages/send_date_request_page.dart';
import 'models/restaurant_model.dart';

import 'services/block_service.dart';
import 'services/notification_service.dart';
import 'services/web_image_helper.dart';
import 'report_service.dart';
import 'identity_verification_service.dart';
import 'screens/group_list_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';


// グローバルナビゲーションキー
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Firebase Storage初期化関数（開発環境のみ）
// Firebase Storage フォルダ構造は手動で作成済みのため、この関数は不要
// Future<void> initializeFirebaseStorage() async {
//   // 削除済み: フォルダ構造は手動で作成済み
// }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // アプリを縦画面のみに制限
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // デバッグ時のオーバーフロー警告を完全に無効にする
  debugPaintSizeEnabled = false;
  debugDisableShadows = false;
  
  // より強力なデバッグ表示の無効化
  if (kDebugMode) {
    // RenderFlexの描画エラー表示を無効化
    debugPrintRebuildDirtyWidgets = false;
    debugPrintBuildScope = false;
  }
  
  // より強力なオーバーフロー関連のエラー無効化
  FlutterError.onError = (FlutterErrorDetails details) {
    final String error = details.exception.toString().toLowerCase();
    // オーバーフロー関連のエラーパターンを拡張
    if (error.contains('renderFlex overflowed'.toLowerCase()) ||
        error.contains('overflowed by') ||
        error.contains('overflowing') ||
        error.contains('bottom overflowed') ||
        error.contains('pixels') ||
        error.contains('renderflex')) {
      // オーバーフローエラーは完全に無視
      return;
    }
    // その他のエラーは通常通り処理
    FlutterError.presentError(details);
  };
  
  // エラーウィジェットを完全に無効化
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // オーバーフロー関連は透明なコンテナを返す
    final String error = details.exception.toString().toLowerCase();
    if (error.contains('overflow') || error.contains('pixels')) {
      return const SizedBox.shrink();
    }
    // その他のエラーは最小限の表示
    return Container(
      color: Colors.transparent,
      child: const SizedBox.shrink(),
    );
  };
  
  try {
    // 日付フォーマット初期化
    await initializeDateFormatting('ja_JP', null);
    
    // Firebase初期化
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Supabase初期化
    await Supabase.initialize(
      url: 'https://krkbpdqxnzozingdbisf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtya2JwZHF4bnpvemluZ2RiaXNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgxNjEyNjIsImV4cCI6MjA2MzczNzI2Mn0.HDPU2bZVeIXs2ylYmUrpmXeLGFQSgsfRGS7wFonBNnQ', // ダッシュボードから取得したanon keyに置き換えてください
    );

    // Firebase Authの言語を日本語に設定
    FirebaseAuth.instance.setLanguageCode('ja');

    // Web版での認証永続化設定
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        
        // Web版での認証状態を確認
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          try {
            await currentUser.getIdToken(true);
          } catch (e) {
          }
        }
      } catch (e) {
      }
    }

    // LINE SDK初期化
    try {
      // Web版ではLINE SDKをスキップ
      if (!kIsWeb) {
        await LineSDK.instance.setup("2007554952").then((_) {
        });
      } else {
      }
    } catch (e) {
    }

    // Firebase Storage初期化
    // Firebase Storage フォルダ構造は手動で作成済み
  // await initializeFirebaseStorage(); // 削除済み

    // バックグラウンドメッセージハンドラーを設定（モバイル版のみ）
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    
    // 通知サービス初期化
    await NotificationService().initialize();
    
  } catch (e, stack) {
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'デリミート - 素敵な出会いと美味しい食事を',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        useMaterial3: false, // Material 3を無効化して元の見た目に戻す
        fontFamily: 'NotoSansJP',
        fontFamilyFallback: ['Inter', 'sans-serif'],
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          margin: EdgeInsets.zero,
        ),
      ),
      navigatorKey: navigatorKey, // グローバルナビゲーションキーを設定
      debugShowCheckedModeBanner: false, // デバッグバナーを非表示
      routes: {
        '/': (context) => const AuthWrapper(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late Stream<User?> _authStateStream;
  StreamSubscription<User?>? _authSubscription;
  User? _currentUser;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _authStateStream = FirebaseAuth.instance.authStateChanges();
    _initializeAuthListener();
  }

  void _initializeAuthListener() {
    // 既存のSubscriptionがあればキャンセル
    _authSubscription?.cancel();
    
    _authSubscription = _authStateStream.listen(
      (User? user) {
        
        if (mounted) {
          setState(() {
            _currentUser = user;
            _isInitialized = true;
          });
        } else {
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      },
    );
    
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    // 初期化待機中
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    // ユーザーが認証されていない場合
    if (_currentUser == null) {
      return const LoginPage();
    }
    
    final user = _currentUser!;
    
    // プロバイダー情報を詳細ログ出力
    for (int i = 0; i < user.providerData.length; i++) {
      final provider = user.providerData[i];
    }
    
    // プロバイダー情報を確認
    final isEmailAuth = user.providerData.any((info) => info.providerId == 'password');
    final isPhoneAuth = user.providerData.any((info) => info.providerId == 'phone');
    final isGoogleAuth = user.providerData.any((info) => info.providerId == 'google.com');
    final isAppleAuth = user.providerData.any((info) => info.providerId == 'apple.com');
    final isLineAuth = user.uid.startsWith('line_');
    
    
    // メール認証チェックをスキップ（パスワード方式に変更）
    // if (isEmailAuth && !user.emailVerified) {
    //   return EmailVerificationWaitingPage(user: user);
    // }
    
    
    // トークンの有効性を確認
    return FutureBuilder<bool>(
      future: _validateTokenAndCheckProfile(user.uid),
      builder: (context, profileSnapshot) {
        
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('ユーザー情報確認中...'),
                ],
              ),
            ),
          );
        }
        
        if (profileSnapshot.hasData && profileSnapshot.data == true) {
          return const DatingFoodApp();
        } else {
          
          // 認証方法を判定
          String authMethod = 'email';
          if (isGoogleAuth) {
            authMethod = 'google';
          } else if (isAppleAuth) {
            authMethod = 'apple';
          } else if (isPhoneAuth) {
            authMethod = 'phone';
          } else if (isLineAuth) {
            authMethod = 'line';
          }
          
          
          return ProfileSetupPage(authMethod: authMethod);
        }
      },
    );
  }

  Future<bool> _validateTokenAndCheckProfile(String uid) async {
    try {
      // トークンの有効性を確認
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return false;
      }

      try {
        await user.getIdToken(true);
      } catch (e) {
        return false;
      }

      // プロフィール確認
      return _ensureUserExistsAndCheckProfile(uid);
    } catch (e) {
      return false;
    }
  }

  Future<bool> _isProfileSetupCompleted(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCompleted = prefs.getBool('profile_setup_completed_$uid') ?? false;
      
      // SharedPreferencesフラグがtrueなら、そのまま返す
      if (isCompleted) {
        return true;
      }
      
      // フラグがfalseの場合、Supabaseで既存ユーザーかチェック
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return false;
      }
      
      try {
        final functions = FirebaseFunctions.instance;
        final callable = functions.httpsCallable('getUserProfile');
        
        final result = await callable.call().timeout(const Duration(seconds: 10));

        
        if (result.data != null) {
          // 既存ユーザーでプロフィールがある場合、フラグを自動設定
          await prefs.setBool('profile_setup_completed_$uid', true);
          return true;
        }
        
        return false;
        
      } catch (e) {
        // エラーの場合は新規ユーザーとして扱う
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }

  Future<bool> _ensureUserExistsAndCheckProfile(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return false;
      }
      
      
      // まず既存ユーザーかどうかをチェック
      try {
        final functions = FirebaseFunctions.instance;
        final callable = functions.httpsCallable('checkExistingUser');
        
        // Web版ではタイムアウトを短縮
        final timeout = kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 12);
        
        final result = await callable.call({
          'uid': uid,
          'email': user.email,
        }).timeout(
          timeout,
          onTimeout: () {
            throw Exception('checkExistingUser timeout');
          },
        );

        
        final exists = result.data['exists'] ?? false;
        final isProfileComplete = result.data['isProfileComplete'] ?? false;
        
        
        if (exists && isProfileComplete) {
          // 既存ユーザーでプロフィール完了済み → メインアプリに進む
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('profile_setup_completed_$uid', true);
          return true;
        } else if (exists && !isProfileComplete) {
          // 既存ユーザーでプロフィール未完了 → プロフィール設定に進む
          return false;
        } else {
          // 新規ユーザー → プロフィール設定に進む（基本情報は作成しない）
          return false;
        }
        
      } catch (e) {
        if (e is FirebaseFunctionsException) {
        }
        // エラーの場合は新規ユーザーとして扱い、プロフィール設定に進む
        return false;
      }
      
    } catch (e) {
      return false;
    }
  }
}

// メインアプリ画面（BottomNavigationBar付き）
class DatingFoodApp extends StatefulWidget {
  const DatingFoodApp({super.key});

  @override
  State<DatingFoodApp> createState() => _DatingFoodAppState();
}

class _DatingFoodAppState extends State<DatingFoodApp> {
  int _selectedIndex = 0;
  
  // バッジ用の変数
  int _newMatchesCount = 0;  // 新しいマッチ数
  int _newLikesCount = 0;    // 新しいいいね数

  // 各画面のWidget
  static const List<Widget> _pages = <Widget>[
    SearchPage(),
    GroupListPage(),
    MatchPage(),
    LikesPage(),
    AccountPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 認証状態が確定してからバッジカウントを読み込み
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBadgeCounts();
    });
  }

  /// バッジカウントを読み込み
  Future<void> _loadBadgeCounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 新しいマッチと新しいいいねの数を取得
      final results = await Future.wait([
        _getNewMatchesCount(),
        _getNewLikesCount(),
      ]);

      if (mounted) {
        setState(() {
          _newMatchesCount = results[0] as int;
          _newLikesCount = results[1] as int;
        });
      }
    } catch (e) {
    }
  }

  /// 新しいマッチ数を取得
  Future<int> _getNewMatchesCount() async {
    // Web版では機能を無効化
    if (kIsWeb) {
      return 0;
    }
    
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getNewMatchesCount');
      final result = await callable().timeout(const Duration(seconds: 3)); // タイムアウト短縮
      return (result.data['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 新しいいいね数を取得
  Future<int> _getNewLikesCount() async {
    // Web版では機能を無効化
    if (kIsWeb) {
      return 0;
    }
    
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getNewLikesCount');
      final result = await callable().timeout(const Duration(seconds: 3)); // タイムアウト短縮
      return (result.data['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  void _onItemTapped(int index) {
    // マッチまたはいいねタブがタップされたらバッジをクリア
    if (index == 2) { // マッチタブ（お気に入り削除で2番目に変更）
      setState(() {
        _newMatchesCount = 0;
      });
    } else if (index == 3) { // いいねタブ（お気に入り削除で3番目に変更）
      setState(() {
        _newLikesCount = 0;
      });
    }
    
    setState(() {
      _selectedIndex = index;
    });
  }

  /// バッジ付きアイコンを作成
  Widget _buildBadgedIcon(IconData icon, int badgeCount) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (badgeCount > 0)
          Positioned(
            top: -8,
            right: -8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.pink,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: '探す',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.group),
            label: 'グループ',
          ),
          BottomNavigationBarItem(
            icon: _buildBadgedIcon(Icons.favorite, _newMatchesCount),
            label: 'マッチ',
          ),
          BottomNavigationBarItem(
            icon: _buildBadgedIcon(Icons.favorite_border, _newLikesCount),
            label: 'いいね',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'アカウント',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}



// 注：以下の_RestaurantSearchPageStateクラスは使用停止
// screens/restaurant_search_page.dartを使用してください
class _RestaurantSearchPageState extends State<RestaurantSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  
  // LIKE機能を追加
  Set<String> _likedRestaurants = {};
  
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
  String? _minPrice;
  String? _maxPrice;
  
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

  static const List<int> _priceOptionsMin = [
    501, 1001, 1501, 2001, 2501, 3001, 3501, 4001, 4501, 5001,
    5501, 6001, 6501, 7001, 7501, 8000, 8500, 9000, 9500, 10000,
    15000, 20000, 25000, 30000,
  ];

  static const List<int> _priceOptionsMax = [
    500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000,
    5500, 6000, 6500, 7000, 7500, 8000, 8500, 9000, 9500, 10000,
    15000, 20000, 25000, 30000,
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
    // 通常の初期検索のみ実行（軽量化）
    _searchRestaurants();
    // LIKE状態を取得
    _loadUserLikes();
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

  Future<void> _searchRestaurants({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _currentLimit = 20; // リセット
      });
    }

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('searchRestaurants');
      
      List<dynamic> allResults = [];
      
      // 複数都道府県対応：選択された都道府県ごとに検索
      if (_selectedPrefectures.isNotEmpty) {
        int totalCountSum = 0;
        for (String prefecture in _selectedPrefectures) {
          Map<String, dynamic> searchParams = {'limit': _currentLimit};
          
          // キーワード検索を追加
          if (_searchController.text.isNotEmpty) {
            searchParams['keyword'] = _searchController.text;
          }
          
          searchParams['prefecture'] = prefecture;
          
          // この都道府県に属する選択された市町村を取得
          final selectedCitiesForPrefecture = _selectedCities.where((city) {
            final citiesInPrefecture = _citiesByPrefecture[prefecture] ?? [];
            return citiesInPrefecture.any((cityData) => cityData['city'] == city);
          }).toList();
          
          if (selectedCitiesForPrefecture.isNotEmpty) {
            // 選択された市町村ごとに個別検索
            for (String city in selectedCitiesForPrefecture) {
              Map<String, dynamic> citySearchParams = Map.from(searchParams);
              citySearchParams['city'] = city;
              
              try {
                final result = await callable(citySearchParams);
                allResults.addAll(List.from(result.data['restaurants'] ?? []));
                // 全件数を累計
                totalCountSum += ((result.data['totalCount'] ?? 0) as num).toInt();
              } catch (e) {
                // エラーがあっても他の市町村の検索は続行
              }
            }
            continue; // 都道府県全体の検索をスキップ
          }
          
          if (_selectedCategories.isNotEmpty) {
            searchParams['category'] = _selectedCategories.first;
          }
          if (_selectedStations.isNotEmpty) {
            searchParams['nearestStation'] = _selectedStations.first;
          }
          
          // 価格帯の処理
          String? priceRange = _buildPriceRangeString();
          if (priceRange != null) {
            searchParams['priceRange'] = priceRange;
          }
          
          try {
            final result = await callable(searchParams);
            allResults.addAll(List.from(result.data['restaurants'] ?? []));
            // 全件数を累計
            totalCountSum += ((result.data['totalCount'] ?? 0) as num).toInt();
          } catch (e) {
            // エラーがあっても他の都道府県の検索は続行
          }
        }
        _totalCount = totalCountSum;
      } else {
        // 都道府県未選択の場合は通常検索
        Map<String, dynamic> searchParams = {'limit': _currentLimit};
        
        // キーワード検索を追加
        if (_searchController.text.isNotEmpty) {
          searchParams['keyword'] = _searchController.text;
        }
        
        if (_selectedCategories.isNotEmpty) {
          searchParams['category'] = _selectedCategories.first;
        }
        if (_selectedStations.isNotEmpty) {
          searchParams['nearestStation'] = _selectedStations.first;
        }
        
        // 価格帯の処理
        String? priceRange = _buildPriceRangeString();
        if (priceRange != null) {
          searchParams['priceRange'] = priceRange;
        }
        
        final result = await callable(searchParams);
        allResults = List.from(result.data['restaurants'] ?? []);
        _totalCount = ((result.data['totalCount'] ?? 0) as num).toInt();
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
      
      // ページネーション対応：指定件数まで制限
      if (finalResults.length > _currentLimit) {
        finalResults = finalResults.take(_currentLimit).toList();
      }
      
      setState(() {
        _searchResults = finalResults;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreResults() async {
    if (_currentLimit >= _maxLimit || _searchResults.length >= _totalCount) return;
    
    int newLimit = (_currentLimit + _incrementLimit).clamp(0, _maxLimit);
    
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('searchRestaurants');
      
      List<dynamic> allResults = [];
      
      // 複数都道府県対応：選択された都道府県ごとに検索
      if (_selectedPrefectures.isNotEmpty) {
        for (String prefecture in _selectedPrefectures) {
          Map<String, dynamic> searchParams = {'limit': newLimit};
          
          // キーワード検索を追加
          if (_searchController.text.isNotEmpty) {
            searchParams['keyword'] = _searchController.text;
          }
          
          searchParams['prefecture'] = prefecture;
          
          // この都道府県に属する選択された市町村を取得
          final selectedCitiesForPrefecture = _selectedCities.where((city) {
            final citiesInPrefecture = _citiesByPrefecture[prefecture] ?? [];
            return citiesInPrefecture.any((cityData) => cityData['city'] == city);
          }).toList();
          
          if (selectedCitiesForPrefecture.isNotEmpty) {
            // 選択された市町村ごとに個別検索
            for (String city in selectedCitiesForPrefecture) {
              Map<String, dynamic> citySearchParams = Map.from(searchParams);
              citySearchParams['city'] = city;
              
              if (_selectedCategories.isNotEmpty) {
                citySearchParams['category'] = _selectedCategories.first;
              }
              if (_selectedStations.isNotEmpty) {
                citySearchParams['nearestStation'] = _selectedStations.first;
              }
              
              // 価格帯の処理
              String? priceRange = _buildPriceRangeString();
              if (priceRange != null) {
                citySearchParams['priceRange'] = priceRange;
              }
              
              try {
                final result = await callable(citySearchParams);
                allResults.addAll(List.from(result.data['restaurants'] ?? []));
              } catch (e) {
              }
            }
            continue; // 都道府県全体の検索をスキップ
          }
          
          if (_selectedCategories.isNotEmpty) {
            searchParams['category'] = _selectedCategories.first;
          }
          if (_selectedStations.isNotEmpty) {
            searchParams['nearestStation'] = _selectedStations.first;
          }
          
          // 価格帯の処理
          String? priceRange = _buildPriceRangeString();
          if (priceRange != null) {
            searchParams['priceRange'] = priceRange;
          }
          
          try {
            final result = await callable(searchParams);
            allResults.addAll(List.from(result.data['restaurants'] ?? []));
          } catch (e) {
          }
        }
      } else {
        // 都道府県未選択の場合は通常検索
        Map<String, dynamic> searchParams = {'limit': newLimit};
        
        // キーワード検索を追加
        if (_searchController.text.isNotEmpty) {
          searchParams['keyword'] = _searchController.text;
        }
        
        if (_selectedCategories.isNotEmpty) {
          searchParams['category'] = _selectedCategories.first;
        }
        if (_selectedStations.isNotEmpty) {
          searchParams['nearestStation'] = _selectedStations.first;
        }
        
        // 価格帯の処理
        String? priceRange = _buildPriceRangeString();
        if (priceRange != null) {
          searchParams['priceRange'] = priceRange;
        }
        
        final result = await callable(searchParams);
        allResults = List.from(result.data['restaurants'] ?? []);
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
      
      setState(() {
        _searchResults = finalResults;
        _currentLimit = newLimit;
      });
      
      
    } catch (e) {
    }
  }

  Future<void> _loadUserLikes() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable();
      
      if (mounted) {
        setState(() {
          // レストランのいいね状態を取得
          _likedRestaurants = Set<String>.from(result.data['likedRestaurants'] ?? []);
        });
      }
      
    } catch (e) {
    }
  }

  Future<void> _toggleRestaurantLike(String restaurantId, bool isCurrentlyLiked) async {
    setState(() {
      if (isCurrentlyLiked) {
        _likedRestaurants.remove(restaurantId);
      } else {
        _likedRestaurants.add(restaurantId);
      }
    });

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        isCurrentlyLiked ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      await callable({'restaurantId': restaurantId});
    } catch (e) {
      setState(() {
        if (isCurrentlyLiked) {
          _likedRestaurants.add(restaurantId);
        } else {
          _likedRestaurants.remove(restaurantId);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LIKE操作に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    
    String? dateStr;
    if (dateValue is String) {
      dateStr = dateValue;
    } else if (dateValue is Map && dateValue.containsKey('liked_at')) {
      dateStr = dateValue['liked_at']?.toString();
    } else {
      dateStr = dateValue.toString();
    }
    
    if (dateStr == null || dateStr.isEmpty) return '';
    
    try {
      final DateTime date = DateTime.parse(dateStr).toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}日前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}時間前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分前';
      } else {
        return 'たった今';
      }
    } catch (e) {
      return '';
    }
  }

  String? _buildPriceRangeString() {
    
    if (_minPrice == null && _maxPrice == null) return null;
    
    int? min = _minPrice != null ? int.tryParse(_minPrice!) : null;
    int? max = _maxPrice != null ? int.tryParse(_maxPrice!) : null;
    
    
    if (min != null && max != null) {
      if (_maxPrice == '30000+') {  // 特別なケース
        return '${min}円～';
      } else {
        return '${min}～${max}円';
      }
    } else if (min != null) {
      return '${min}円～';
    } else if (max != null) {
      if (_maxPrice == '30000+') {  // 特別なケース
        return '30001円～';
      } else {
        return '～${max}円';
      }
    }
    
    return null;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedPrefectures.clear();
      _selectedCities.clear();
      _selectedCategories.clear();
      _selectedStations.clear();
      _minPrice = null;
      _maxPrice = null;
      _searchController.clear();
      _currentLimit = 20; // ページネーション変数もリセット
    });
    _searchRestaurants();
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

  List<String> _getStationsForSelectedPrefectures() {
    if (_selectedPrefectures.isEmpty) return [];
    
    List<String> stations = [];
    for (String prefecture in _selectedPrefectures) {
      if (_stationsByPrefecture.containsKey(prefecture)) {
        stations.addAll(_stationsByPrefecture[prefecture]!);
      }
    }
    return stations;
  }

  int _getActiveFilterCount() {
    int count = 0;
    count += _selectedPrefectures.length;
    count += _selectedCities.length;
    count += _selectedCategories.length;
    count += _selectedStations.length;
    if (_minPrice != null || _maxPrice != null) count += 1;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('レストランを探す'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.clear_all),
            tooltip: 'フィルタークリア',
          ),
        ],
      ),
      body: Column(
        children: [
          // 検索バー
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'レストラン名で検索...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _searchRestaurants(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searchRestaurants,
                  child: const Text('検索'),
                ),
              ],
            ),
          ),

          // フィルターエリア（折りたたみ可能）
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
            ),
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
                              color: Colors.pink,
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
                              _buildFilterChip(
                                '都道府県',
                                _selectedPrefectures,
                                'prefecture',
                              ),
                              const SizedBox(width: 8),
                              
                              // 市町村フィルター（都道府県が選択されている場合のみ表示）
                              if (_selectedPrefectures.isNotEmpty)
                                _buildCityFilterChip(),
                              if (_selectedPrefectures.isNotEmpty)
                                const SizedBox(width: 8),
                              
                              _buildFilterChip(
                                'カテゴリ',
                                _selectedCategories,
                                'category',
                              ),
                              const SizedBox(width: 8),
                              _buildPriceFilterChip(),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                '最寄駅',
                                _selectedStations,
                                'station',
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
                                _buildSelectedFilterChip('price', _buildPriceRangeString() ?? '価格設定'),
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
                : Column(
                    children: [
                      // 検索結果件数表示
                      if (_searchResults.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            '検索結果: ${_totalCount}件中${_searchResults.length}件表示',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      
                      // 検索結果リスト
                      Expanded(
                        child: _searchResults.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off, size: 64, color: Colors.grey),
                                    SizedBox(height: 16),
                                    Text(
                                      '検索結果がありません',
                                      style: TextStyle(fontSize: 18, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final restaurant = _searchResults[index];
                                  final restaurantId = restaurant['id'] ?? '';
                                  final isLiked = _likedRestaurants.contains(restaurantId);
                                  
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
                                        // TODO: レストラン詳細画面への遷移
                                      },
                                      child: Container(
                                        height: 118, // カードの高さを調整
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 左側の画像
                                            ClipRRect(
                                              borderRadius: const BorderRadius.horizontal(
                                                left: Radius.circular(16),
                                              ),
                                              child: SizedBox(
                                                width: 118, // 画像サイズを調整
                                                height: 118,
                                                child: WebImageHelper.buildRestaurantImage(
                                                  restaurant['image_url'],
                                                  width: 118,
                                                  height: 118,
                                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                                ),
                                              ),
                                            ),
                                            // 右側の情報
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // 店名といいねボタンを横並び
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            restaurant['name'] ?? 'レストラン名未設定',
                                                            style: const TextStyle(
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                            maxLines: 2,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        // いいねボタン
                                                        GestureDetector(
                                                          onTap: () {
                                                            _toggleRestaurantLike(restaurantId, isLiked);
                                                          },
                                                          child: Container(
                                                            padding: const EdgeInsets.all(6),
                                                            decoration: BoxDecoration(
                                                              color: isLiked ? Colors.pink : Colors.grey[200],
                                                              borderRadius: BorderRadius.circular(12),
                                                            ),
                                                            child: Icon(
                                                              isLiked ? Icons.favorite : Icons.favorite_border,
                                                              color: isLiked ? Colors.white : Colors.grey[600],
                                                              size: 16,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // カテゴリ
                                                    if (restaurant['category'] != null)
                                                      Text(
                                                        restaurant['category'].toString(),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey[600],
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    const SizedBox(height: 2),
                                                    // 都道府県と最寄り駅
                                                    Row(
                                                      children: [
                                                        // 都道府県
                                                        if (restaurant['prefecture'] != null) ...[
                                                          Icon(
                                                            Icons.location_on,
                                                            size: 10,
                                                            color: Colors.grey[500],
                                                          ),
                                                          const SizedBox(width: 1),
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
                                                          const SizedBox(width: 1),
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
                                                    const SizedBox(height: 2),
                                                    // 価格帯
                                                    if (restaurant['price_range'] != null)
                                                      Row(
                                                        children: [
                                                          Icon(
                                                            Icons.monetization_on,
                                                            size: 10,
                                                            color: Colors.pink[400],
                                                          ),
                                                          const SizedBox(width: 1),
                                                          Text(
                                                            restaurant['price_range'].toString(),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors.pink[600],
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ],
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
                      
                      // もっと探すボタン
                      if (_searchResults.isNotEmpty && _searchResults.length < _totalCount && _currentLimit < _maxLimit)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          child: ElevatedButton(
                            onPressed: _loadMoreResults,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pink,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: Text(
                              'もっと探す（最大${_maxLimit}件）',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    List<String> selectedValues,
    String type,
  ) {
    return FilterChip(
      label: Text(selectedValues.isEmpty ? label : '${label}(${selectedValues.length})'),
      selected: selectedValues.isNotEmpty,
      onSelected: (bool selected) {
        _showFilterDialog(label, type);
      },
      selectedColor: Colors.pink[100],
      checkmarkColor: Colors.pink,
    );
  }

  Widget _buildCityFilterChip() {
    return FilterChip(
      label: Text(
        _selectedCities.isEmpty
            ? '市町村'
            : '${_selectedCities.length}件選択中',
      ),
      selected: _selectedCities.isNotEmpty,
      onSelected: (_) => _showCitySelectionDialog(),
      selectedColor: Colors.pink[100],
      checkmarkColor: Colors.pink,
    );
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
                                    color: Colors.pink[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    prefecture,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.pink,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // 市町村リスト（最適化）
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

  Widget _buildPriceFilterChip() {
    bool hasPrice = _minPrice != null || _maxPrice != null;
    return FilterChip(
      label: Text(hasPrice ? '価格帯(設定済み)' : '価格帯'),
      selected: hasPrice,
      onSelected: (bool selected) {
        _showPriceDialog();
      },
      selectedColor: Colors.pink[100],
      checkmarkColor: Colors.pink,
    );
  }

  Widget _buildSelectedFilterChip(String type, String value) {
    return Chip(
      label: Text(value),
      backgroundColor: Colors.pink[50],
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: () => _removeFilter(type, value),
    );
  }

  void _showFilterDialog(String title, String type) {
    List<String> options;
    List<String> currentSelected;
    
    switch (type) {
      case 'prefecture':
        options = _prefectures;
        currentSelected = _selectedPrefectures;
        break;
      case 'category':
        options = _categories;
        currentSelected = _selectedCategories;
        break;
      case 'station':
        options = _getStationsForSelectedPrefectures();
        currentSelected = _selectedStations;
        if (options.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('まず都道府県を選択してください')),
          );
          return;
        }
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text('${title}を選択'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: ListView.builder(
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    
                    return CheckboxListTile(
                      title: Text(option),
                      value: currentSelected.contains(option),
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            if (!currentSelected.contains(option)) {
                              currentSelected.add(option);
                            }
                          } else {
                            currentSelected.remove(option);
                          }
                        });
                        setState(() {
                          // 都道府県が変更された場合、関連する選択をリセット
                          if (type == 'prefecture') {
                            // 選択された都道府県に含まれない駅を除外
                            _selectedStations.removeWhere((station) {
                              return !_selectedPrefectures.any((prefecture) =>
                                  _stationsByPrefecture[prefecture]?.contains(station) == true);
                            });
                            // 選択された都道府県に含まれない市町村を除外
                            _selectedCities.removeWhere((city) {
                              return !_selectedPrefectures.any((prefecture) {
                                final citiesInPrefecture = _citiesByPrefecture[prefecture] ?? [];
                                return citiesInPrefecture.any((cityData) => cityData['city'] == city);
                              });
                            });
                            
                            // 新しく選択された都道府県の市町村データを事前取得（バックグラウンド）
                            _preloadCitiesForSelectedPrefectures();
                          }
                        }); // 外側のstateも更新
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPriceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
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
                        child: DropdownButton<String>(
                          value: _minPrice,
                          hint: const Text('選択してください'),
                          isExpanded: true,
                          items: [
                            ..._priceOptionsMin.map((price) {
                              return DropdownMenuItem(
                                value: price.toString(),
                                child: Text('${price}円'),
                              );
                            }),
                          ],
                          onChanged: (String? value) {
                            setDialogState(() {
                              _minPrice = value;
                            });
                            setState(() {});
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
                        child: DropdownButton<String>(
                          value: _maxPrice,
                          hint: const Text('選択してください'),
                          isExpanded: true,
                          items: [
                            ..._priceOptionsMax.map((price) {
                              return DropdownMenuItem(
                                value: price.toString(),
                                child: Text('${price}円'),
                              );
                            }),
                          ],
                          onChanged: (String? value) {
                            setDialogState(() {
                              _maxPrice = value;
                            });
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      _minPrice = null;
                      _maxPrice = null;
                    });
                    setState(() {});
                  },
                  child: const Text('クリア'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ユーザー検索画面
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _nameController = TextEditingController();
  List<dynamic> _searchResults = [];
  List<dynamic> _recommendedUsers = []; // 追加：おすすめユーザーリスト
  bool _isLoading = false;
  int _totalCount = 0;
  
  // ページネーション用の変数
  int _currentLimit = 20;
  final int _maxLimit = 50;
  final int _incrementLimit = 10;
  
  // LIKE機能
  Set<String> _likedUsers = {};
  Set<String> _likedRestaurants = {}; // レストランのいいね状態を管理
  
  // フィルター用の変数
  int? _minAge;
  int? _maxAge;
  List<String> _selectedGenders = [];
  List<String> _selectedOccupations = [];
  bool? _weekendOff;
  List<String> _selectedFavoriteCategories = [];
  bool? _idVerified;
  
  // 固定オプション
  static const List<String> _genders = ['男性', '女性', 'その他'];
  
  static const List<String> _occupations = [
    '会社員', 'エンジニア', '医療従事者', '教育関係', '公務員', 
    'フリーランス', '学生', 'その他'
  ];
  
  static const List<String> _categories = [
    '居酒屋', 'カラオケ・パーティ', 'バー・カクテル', 'ラーメン', '和食', '韓国料理',
    'カフェ・スイーツ', '焼肉・ホルモン', 'アジア・エスニック料理', '洋食', '中華',
    'ダイニングバー・バル', 'イタリアン・フレンチ', 'その他グルメ', 'お好み焼き・もんじゃ',
    '各国料理', '創作料理',
  ];

  @override
  void initState() {
    super.initState();
    _searchUsers();
    _loadUserLikes();
  }

  Future<void> _searchUsers() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _currentLimit = 20; // リセット
    });

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('searchUsers');
      
      Map<String, dynamic> searchParams = {'limit': _currentLimit};
      
      if (_nameController.text.isNotEmpty) {
        searchParams['keyword'] = _nameController.text;
      }
      
      if (_minAge != null) {
        searchParams['minAge'] = _minAge;
      }
      
      if (_maxAge != null) {
        searchParams['maxAge'] = _maxAge;
      }
      
      if (_selectedGenders.isNotEmpty) {
        searchParams['genders'] = _selectedGenders;
      }
      
      if (_selectedOccupations.isNotEmpty) {
        searchParams['occupations'] = _selectedOccupations;
      }
      
      if (_weekendOff != null) {
        searchParams['weekendOff'] = _weekendOff;
      }
      
      if (_selectedFavoriteCategories.isNotEmpty) {
        searchParams['favoriteCategories'] = _selectedFavoriteCategories;
      }
      
      if (_idVerified != null) {
        searchParams['idVerified'] = _idVerified;
      }
      
      final result = await callable(searchParams);
      
      if (mounted) {
      setState(() {
        _searchResults = List.from(result.data['users'] ?? []);
          _recommendedUsers = List.from(result.data['users'] ?? []); // 追加：おすすめユーザーも同じデータで更新
        _totalCount = ((result.data['totalCount'] ?? 0) as num).toInt();
        _isLoading = false;
      });
      }
      
    } catch (e) {
      if (mounted) {
      setState(() {
        _isLoading = false;
      });
      }
    }
  }

  Future<void> _loadMoreResults() async {
    if (_currentLimit >= _maxLimit || _searchResults.length >= _totalCount) return;
    
    int newLimit = (_currentLimit + _incrementLimit).clamp(0, _maxLimit);
    
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('searchUsers');
      
      Map<String, dynamic> searchParams = {'limit': newLimit};
      
      if (_nameController.text.isNotEmpty) {
        searchParams['keyword'] = _nameController.text;
      }
      
      if (_minAge != null) {
        searchParams['minAge'] = _minAge;
      }
      
      if (_maxAge != null) {
        searchParams['maxAge'] = _maxAge;
      }
      
      if (_selectedGenders.isNotEmpty) {
        searchParams['genders'] = _selectedGenders;
      }
      
      if (_selectedOccupations.isNotEmpty) {
        searchParams['occupations'] = _selectedOccupations;
      }
      
      if (_weekendOff != null) {
        searchParams['weekendOff'] = _weekendOff;
      }
      
      if (_selectedFavoriteCategories.isNotEmpty) {
        searchParams['favoriteCategories'] = _selectedFavoriteCategories;
      }
      
      if (_idVerified != null) {
        searchParams['idVerified'] = _idVerified;
      }
      
      final result = await callable(searchParams);
      
      if (mounted) {
      setState(() {
        _searchResults = List.from(result.data['users'] ?? []);
          _recommendedUsers = List.from(result.data['users'] ?? []); // 追加：おすすめユーザーも同じデータで更新
        _totalCount = ((result.data['totalCount'] ?? 0) as num).toInt();
        _currentLimit = newLimit;
      });
      }
      
    } catch (e) {
    }
  }

  Future<void> _loadUserLikes() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable();
      
      if (mounted) {
      setState(() {
          // レストランのいいね状態を取得
          _likedRestaurants = Set<String>.from(result.data['likedRestaurants'] ?? []);
          
          // ユーザーのいいね状態も取得
          final sentLikes = List.from(result.data['sentLikes'] ?? []);
          _likedUsers = Set<String>.from(
            sentLikes.map((like) => like['liked_user_id']?.toString() ?? '').where((id) => id.isNotEmpty)
          );
        });
      }
      
    } catch (e) {
    }
  }

  /// ネットワーク画像表示（色補正なし）
  Widget _buildNetworkImageWithColorCorrection(String imageUrl) {
    return WebImageHelper.buildProfileImage(
      imageUrl,
      size: 40,
      isCircular: false,
    );
  }

  Future<void> _toggleUserLike(String userId, bool isCurrentlyLiked) async {
    if (!mounted) return;
    
    // 既にいいね済みの場合は何もしない（取り消し不可）
    if (isCurrentlyLiked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('いいねは取り消すことができません'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 楽観的更新：UIを先に更新（いいね追加のみ）
    setState(() {
      _likedUsers.add(userId);
    });

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('addUserLike');
      final result = await callable({'likedUserId': userId});
      
      // マッチチェック
      if (result.data['isMatch'] == true) {
        
        // マッチ通知を表示
        if (mounted) {
          _showMatchDialog(userId, result.data['matchId']);
        }
      }
      
      // 成功時は既にUIが更新されているので何もしない
    } catch (e) {
      
      // エラー時はUIを元に戻す
      if (mounted) {
      setState(() {
        _likedUsers.remove(userId);  // 元に戻す
      });
      }
      
      // エラーメッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LIKE操作に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearAllFilters() {
    setState(() {
      _nameController.clear();
      _minAge = null;
      _maxAge = null;
      _selectedGenders.clear();
      _selectedOccupations.clear();
      _weekendOff = null;
      _selectedFavoriteCategories.clear();
      _idVerified = null;
      _currentLimit = 20; // ページネーション変数もリセット
    });
  }

  // ブロック機能
  Future<void> _blockUser(String userId, String userName) async {
    // 確認ダイアログを表示
    final shouldBlock = await BlockService.showBlockConfirmDialog(
      context,
      userName,
    );

    if (!shouldBlock) return;

    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final success = await BlockService.blockUser(userId);
      
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${userName}さんをブロックしました'),
              backgroundColor: Colors.green,
            ),
          );
          // 検索結果を再読み込み（ブロックしたユーザーを除外）
          _searchUsers();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ブロックに失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMatchDialog(String userId, String matchId) {
    // マッチした相手の情報を探す
    final matchedUser = _recommendedUsers.firstWhere(
      (user) => user['id'] == userId,
      orElse: () => null,
    );
    
    final partnerName = matchedUser?['name'] ?? '名前未設定';
    final partnerImageUrl = matchedUser?['image_url'];
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // マッチアニメーション
              Container(
                padding: const EdgeInsets.all(20),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.pink,
                  size: 80,
                ),
              ),
              const Text(
                '🎉 マッチ成立！ 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // 相手の情報
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: partnerImageUrl != null
                        ? NetworkImage(partnerImageUrl)
                        : null,
                    child: partnerImageUrl == null
                        ? const Icon(Icons.person, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.favorite, color: Colors.pink, size: 24),
                  const SizedBox(width: 16),
                  const CircleAvatar(
                    radius: 30,
                    child: Icon(Icons.person, size: 30),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${partnerName}さんとマッチしました！\nメッセージを送って会話を始めましょう。',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('後で'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // マッチ詳細画面へ遷移
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MatchDetailPage(
                      matchId: matchId,
                      partnerName: partnerName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
              ),
              child: const Text('メッセージを送る'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('人を探す'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _searchUsers();
            },
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
          ),
          IconButton(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.clear_all),
            tooltip: 'フィルタークリア',
          ),
        ],
      ),
      body: Column(
        children: [
          // 検索条件エリア
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[50],
            child: Column(
              children: [
                // 名前検索
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: '名前で検索...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_search),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _searchUsers(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _searchUsers,
                      child: const Text('検索'),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // フィルターボタン行
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildAgeFilterChip(),
                      const SizedBox(width: 8),
                      _buildMultiSelectChip('性別', _selectedGenders, _genders),
                      const SizedBox(width: 8),
                      _buildMultiSelectChip('職業', _selectedOccupations, _occupations),
                      const SizedBox(width: 8),
                      _buildBooleanFilterChip('土日休み', _weekendOff, (value) {
                        setState(() {
                          _weekendOff = value;
                        });
                      }),
                      const SizedBox(width: 8),
                      _buildMultiSelectChip('好きなカテゴリ', _selectedFavoriteCategories, _categories),
                      const SizedBox(width: 8),
                      _buildBooleanFilterChip('身分証明書済み', _idVerified, (value) {
                        setState(() {
                          _idVerified = value;
                        });
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 検索結果
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // 検索結果件数表示
                      if (_searchResults.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            '検索結果: ${_totalCount}件中${_searchResults.length}件表示',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      
                      // ユーザーリスト
                      Expanded(
                        child: _searchResults.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_search, size: 64, color: Colors.grey),
                                    SizedBox(height: 16),
                                    Text(
                                      '該当するユーザーがいません',
                                      style: TextStyle(fontSize: 18, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = _searchResults[index];
                                  final userId = user['uid'] ?? user['id'] ?? '';
                                  final isLiked = _likedUsers.contains(userId);
                                  
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
                                        // プロフィール画面に遷移
                                        final userIdToUse = user['uid'] ?? user['id'] ?? '';
                                        if (userIdToUse.isNotEmpty) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ProfileViewPage(
                                                userId: userIdToUse,
                                              ),
                                            ),
                                          );
                                        } else {
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            // プロフィール画像（大きいサイズ）
                                            Container(
                                              width: 120,
                                              height: 120,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                color: Colors.grey[300],
                                              ),
                                                                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: user['image_url'] != null
                                    ? (kIsWeb
                                        ? WebImageHelper.buildImage(
                                            user['image_url'],
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            borderRadius: BorderRadius.circular(12),
                                            errorWidget: const Icon(Icons.person, size: 60, color: Colors.grey),
                                          )
                                        : _buildNetworkImageWithColorCorrection(user['image_url']))
                                    : const Icon(Icons.person, size: 60, color: Colors.grey),
                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            // ユーザー情報
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        user['name'] ?? '名前未設定',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      if (user['id_verified'] == true) ...[
                                                        const SizedBox(width: 8),
                                                        const Icon(
                                                          Icons.verified,
                                                          color: Colors.blue,
                                                          size: 16,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${user['age']?.toString() ?? '?'}歳${user['prefecture'] != null ? '・${user['prefecture']}' : ''}',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  if (user['occupation'] != null) ...[
                                                    const SizedBox(height: 4),
                                                    Text('💼 ${user['occupation']}'),
                                                  ],
                                                  if (user['weekend_off'] == true) ...[
                                                    const SizedBox(height: 4),
                                                    const Text('📅 土日休み'),
                                                  ],
                                                  if (user['favorite_categories'] != null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '❤️ ${(user['favorite_categories'] as List).join(', ')}',
                                                      style: const TextStyle(fontSize: 12),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            // アクションボタン
                                            Column(
                                              children: [
                                                // ブロックボタン
                                                GestureDetector(
                                                  onTap: () async {
                                                    final userIdToUse = user['uid'] ?? user['id'] ?? '';
                                                    final userName = user['name'] ?? '名前未設定';
                                                    if (userIdToUse.isNotEmpty) {
                                                      await _blockUser(userIdToUse, userName);
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red[50],
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      Icons.block,
                                                      color: Colors.red[600],
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                // いいねボタン
                                                GestureDetector(
                                                  onTap: () {
                                                    final userIdToUse = user['uid'] ?? user['id'] ?? '';
                                                    if (userIdToUse.isNotEmpty) {
                                                      _toggleUserLike(userIdToUse, isLiked);
                                                    }
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: isLiked ? Colors.pink : Colors.grey[200],
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      Icons.favorite,
                                                      color: isLiked ? Colors.white : Colors.grey[600],
                                                      size: 20,
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
                                },
                              ),
                      ),
                      
                      // もっと探すボタン
                      if (_searchResults.isNotEmpty && _searchResults.length < _totalCount && _currentLimit < _maxLimit)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          child: ElevatedButton(
                            onPressed: _loadMoreResults,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pink,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: Text(
                              'もっと探す（最大${_maxLimit}件）',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgeFilterChip() {
    String label = '年齢';
    if (_minAge != null || _maxAge != null) {
      label = '年齢(';
      if (_minAge != null && _maxAge != null) {
        label += '${_minAge}～${_maxAge}歳';
      } else if (_minAge != null) {
        label += '${_minAge}歳～';
      } else if (_maxAge != null) {
        label += '～${_maxAge}歳';
      }
      label += ')';
    }
    
    return FilterChip(
      label: Text(label),
      selected: _minAge != null || _maxAge != null,
      onSelected: (_) => _showAgeDialog(),
      selectedColor: Colors.pink[100],
      checkmarkColor: Colors.pink,
    );
  }

  Widget _buildMultiSelectChip(String label, List<String> selectedValues, List<String> options) {
    return FilterChip(
      label: Text(selectedValues.isEmpty ? label : '$label(${selectedValues.length})'),
      selected: selectedValues.isNotEmpty,
      onSelected: (_) => _showMultiSelectDialog(label, selectedValues, options),
      selectedColor: Colors.pink[100],
      checkmarkColor: Colors.pink,
    );
  }

  Widget _buildBooleanFilterChip(String label, bool? value, Function(bool?) onChanged) {
    String displayLabel = label;
    if (value != null) {
      displayLabel = '$label(${value ? 'はい' : 'いいえ'})';
    }
    
    return FilterChip(
      label: Text(displayLabel),
      selected: value != null,
      onSelected: (_) => _showBooleanDialog(label, value, onChanged),
      selectedColor: Colors.pink[100],
      checkmarkColor: Colors.pink,
    );
  }

  void _showAgeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('年齢を選択'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('最小年齢: '),
                Expanded(
                  child: DropdownButton<int>(
                    value: _minAge,
                    hint: const Text('選択'),
                    isExpanded: true,
                    items: List.generate(82, (index) => index + 18)
                        .map((age) => DropdownMenuItem(
                              value: age,
                              child: Text('${age}歳'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _minAge = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('最大年齢: '),
                Expanded(
                  child: DropdownButton<int>(
                    value: _maxAge,
                    hint: const Text('選択'),
                    isExpanded: true,
                    items: List.generate(82, (index) => index + 18)
                        .map((age) => DropdownMenuItem(
                              value: age,
                              child: Text('${age}歳'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _maxAge = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _minAge = null;
                _maxAge = null;
              });
            },
            child: const Text('クリア'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showMultiSelectDialog(String title, List<String> selectedValues, List<String> options) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${title}を選択'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return CheckboxListTile(
                  title: Text(option),
                  value: selectedValues.contains(option),
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        selectedValues.add(option);
                      } else {
                        selectedValues.remove(option);
                      }
                    });
                    setState(() {});
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBooleanDialog(String title, bool? currentValue, Function(bool?) onChanged) {
    bool? tempValue = currentValue; // 一時的な値を保持
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool?>(
                title: const Text('指定しない'),
                value: null,
                groupValue: tempValue,
                onChanged: (value) {
                  setDialogState(() {
                    tempValue = value;
                  });
                  onChanged(value);
                  setState(() {}); // 外側のstateも更新
                },
              ),
              RadioListTile<bool?>(
                title: const Text('はい'),
                value: true,
                groupValue: tempValue,
                onChanged: (value) {
                  setDialogState(() {
                    tempValue = value;
                  });
                  onChanged(value);
                  setState(() {}); // 外側のstateも更新
                },
              ),
              RadioListTile<bool?>(
                title: const Text('いいえ'),
                value: false,
                groupValue: tempValue,
                onChanged: (value) {
                  setDialogState(() {
                    tempValue = value;
                  });
                  onChanged(value);
                  setState(() {}); // 外側のstateも更新
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    
    String? dateStr;
    if (dateValue is String) {
      dateStr = dateValue;
    } else if (dateValue is Map && dateValue.containsKey('liked_at')) {
      dateStr = dateValue['liked_at']?.toString();
    } else {
      dateStr = dateValue.toString();
    }
    
    if (dateStr == null || dateStr.isEmpty) return '';
    
    try {
      final DateTime date = DateTime.parse(dateStr).toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}日前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}時間前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分前';
      } else {
        return 'たった今';
      }
    } catch (e) {
      return '';
    }
  }

  // マッチアクション選択ダイアログを表示
  void _showMatchActionDialog(BuildContext context, Map<String, dynamic> match, String partnerName, String partnerId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$partnerNameさんとの操作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: const Text('プロフィールを見る'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(
                        userId: partnerId,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.green),
                title: const Text('メッセージを送る'),
                onTap: () {
                  Navigator.of(context).pop();
                  // マッチ詳細画面への遷移
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatchDetailPage(
                        matchId: match['id'],
                        partnerName: partnerName,
                      ),
                    ),
                  ).then((_) {
                    _searchUsers();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('ブロックする'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showBlockConfirmDialog(context, partnerId, partnerName);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  // ブロック確認ダイアログを表示
  void _showBlockConfirmDialog(BuildContext context, String userId, String userName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ブロック確認'),
          content: Text('$userNameさんをブロックしますか？\nブロックすると、お互いのプロフィールが表示されなくなり、メッセージの送受信もできなくなります。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _blockUser(userId, userName);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('ブロックする'),
            ),
          ],
        );
      },
    );
  }

}

// お気に入りのお店画面
class FavoriteStoresPage extends StatefulWidget {
  const FavoriteStoresPage({super.key});

  @override
  State<FavoriteStoresPage> createState() => _FavoriteStoresPageState();
}

class _FavoriteStoresPageState extends State<FavoriteStoresPage> {
  List<dynamic> _likedRestaurants = [];
  bool _isLoading = true;
  Set<String> _likedRestaurantIds = {};

  @override
  void initState() {
    super.initState();
    _loadLikedRestaurants();
  }

  Future<void> _loadLikedRestaurants() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // いいねしたレストランの詳細情報を直接取得（タイムアウト短縮で高速化）
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getLikedRestaurants');
      final result = await callable().timeout(const Duration(seconds: 3));
      
      final List<dynamic> restaurants = List.from(result.data['restaurants'] ?? []);
      
      if (mounted) {
        setState(() {
          _likedRestaurants = restaurants;
          _likedRestaurantIds = Set<String>.from(
            restaurants.map((restaurant) => restaurant['id']?.toString() ?? '')
          );
          _isLoading = false;
        });
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('更新ボタンを押してください'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _toggleRestaurantLike(String restaurantId, bool isCurrentlyLiked) async {
    if (!mounted) return;
    
    setState(() {
      if (isCurrentlyLiked) {
        _likedRestaurantIds.remove(restaurantId);
        _likedRestaurants.removeWhere((restaurant) => restaurant['id'] == restaurantId);
      } else {
        _likedRestaurantIds.add(restaurantId);
      }
    });

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        isCurrentlyLiked ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      await callable({'restaurantId': restaurantId});
      
      // いいねを外した場合は一覧から削除済み、追加した場合は再読み込み
      if (!isCurrentlyLiked) {
        _loadLikedRestaurants();
      }
    } catch (e) {
      // エラー時はUIを元に戻す
      if (mounted) {
        setState(() {
          if (isCurrentlyLiked) {
            _likedRestaurantIds.add(restaurantId);
          } else {
            _likedRestaurantIds.remove(restaurantId);
          }
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LIKE操作に失敗しました'),
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
        title: const Text('お気に入りのお店'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadLikedRestaurants,
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _likedRestaurants.isEmpty
              ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                      Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 20),
            Text(
                        'まだお気に入りのお店がありません',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
                      Text(
                        '素敵なお店を見つけて、いいねしてみましょう！',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLikedRestaurants,
                  child: ListView.builder(
                    itemCount: _likedRestaurants.length,
                    itemBuilder: (context, index) {
                      final restaurant = _likedRestaurants[index];
                      final restaurantId = restaurant['id'] ?? '';
                      final isLiked = _likedRestaurantIds.contains(restaurantId);
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        child: InkWell(
                          onTap: () {
                            // TODO: レストラン詳細画面への遷移
                          },
                          child: Container(
                            height: 118, // カードの高さを調整
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 左側の画像
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(16),
                                  ),
                                  child: SizedBox(
                                    width: 118, // 画像サイズを調整
                                    height: 118,
                                    child: WebImageHelper.buildRestaurantImage(
                                      restaurant['image_url'],
                                      width: 118,
                                      height: 118,
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                    ),
                                  ),
                                ),
                                // 右側の情報
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 店名といいねボタンを横並び
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                restaurant['name'] ?? 'レストラン名未設定',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            // いいねボタン
                                            GestureDetector(
                                              onTap: () {
                                                _toggleRestaurantLike(restaurantId, isLiked);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: isLiked ? Colors.pink : Colors.grey[200],
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                                  color: isLiked ? Colors.white : Colors.grey[600],
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // カテゴリ
                                        if (restaurant['category'] != null)
                                          Text(
                                            restaurant['category'].toString(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        const SizedBox(height: 2),
                                        // 都道府県と最寄り駅
                                        Row(
                                          children: [
                                            // 都道府県
                                            if (restaurant['prefecture'] != null) ...[
                                              Icon(
                                                Icons.location_on,
                                                size: 10,
                                                color: Colors.grey[500],
                                              ),
                                              const SizedBox(width: 1),
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
                                              const SizedBox(width: 1),
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
                                        const SizedBox(height: 2),
                                        // 価格帯
                                        if (restaurant['price_range'] != null)
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.monetization_on,
                                                size: 10,
                                                color: Colors.pink[400],
                                              ),
                                              const SizedBox(width: 1),
                                              Text(
                                                restaurant['price_range'].toString(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.pink[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
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
    );
  }
}



// いいね一覧画面（旧版 - 削除予定）
class OldLikesPage extends StatefulWidget {
  const OldLikesPage({super.key});

  @override
  State<OldLikesPage> createState() => _OldLikesPageState();
}

class _OldLikesPageState extends State<OldLikesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _sentLikes = [];
  List<dynamic> _receivedLikes = [];
  bool _isLoading = true;
  Set<String> _likedUsers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLikes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLikes() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable();
      
      if (mounted) {
        setState(() {
          _sentLikes = result.data['sentLikes'] ?? [];
          _receivedLikes = result.data['receivedLikes'] ?? [];
          _isLoading = false;
          
          // 送信したいいねからユーザーIDを取得
          _likedUsers = Set<String>.from(
            _sentLikes.map((like) => like['liked_user_id']?.toString() ?? '').where((id) => id.isNotEmpty)
          );
          
          
          // 受信したいいねのデータ構造をデバッグ出力
          if (_receivedLikes.isNotEmpty) {
          }
        });
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('いいね一覧の取得に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleUserLike(String userId, bool isCurrentlyLiked) async {
    if (!mounted) return;
    
    // 既にいいね済みの場合は何もしない（取り消し不可）
    if (isCurrentlyLiked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('いいねは取り消すことができません'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 楽観的更新：UIを先に更新（いいね追加のみ）
    setState(() {
      _likedUsers.add(userId);
    });

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('addUserLike');
      final result = await callable({'likedUserId': userId});
      
      // マッチチェック
      if (result.data['isMatch'] == true) {
        
        // マッチ通知を表示
        if (mounted) {
          _showMatchDialog(userId, result.data['matchId']);
        }
      }
      
      // 成功時はいいね状態を再読み込みして確実に同期
      
      // いいね状態を再読み込み（確実な同期のため）
      _loadLikes();
    } catch (e) {
      
      // エラー時はUIを元に戻す
      if (mounted) {
        setState(() {
          _likedUsers.remove(userId);  // 元に戻す
        });
      }
      
      // エラーメッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LIKE操作に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ブロック機能
  Future<void> _blockUser(String userId, String userName) async {
    // 確認ダイアログを表示
    final shouldBlock = await BlockService.showBlockConfirmDialog(
      context,
      userName,
    );

    if (!shouldBlock) return;

    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final success = await BlockService.blockUser(userId);
      
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${userName}さんをブロックしました'),
              backgroundColor: Colors.green,
            ),
          );
          // いいね一覧を再読み込み（ブロックしたユーザーを除外）
          _loadLikes();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ブロックに失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMatchDialog(String userId, String matchId) {
    // マッチした相手の情報を探す
    final matchedUser = _receivedLikes.firstWhere(
      (user) => user['user_id'] == userId,
      orElse: () => null,
    );
    
    final partnerName = matchedUser?['name'] ?? '名前未設定';
    final partnerImageUrl = matchedUser?['image_url'];
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // マッチアニメーション
              Container(
                padding: const EdgeInsets.all(20),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.pink,
                  size: 80,
                ),
              ),
              const Text(
                '🎉 マッチ成立！ 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // 相手の情報
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: partnerImageUrl != null
                        ? NetworkImage(partnerImageUrl)
                        : null,
                    child: partnerImageUrl == null
                        ? const Icon(Icons.person, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.favorite, color: Colors.pink, size: 24),
                  const SizedBox(width: 16),
                  const CircleAvatar(
                    radius: 30,
                    child: Icon(Icons.person, size: 30),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${partnerName}さんとマッチしました！\nメッセージを送って会話を始めましょう。',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('後で'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // マッチ詳細画面へ遷移
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MatchDetailPage(
                      matchId: matchId,
                      partnerName: partnerName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
              ),
              child: const Text('メッセージを送る'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('いいね'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '送信したいいね'),
            Tab(text: '受信したいいね'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadLikes,
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSentLikesTab(),
                _buildReceivedLikesTab(),
              ],
            ),
    );
  }

  Widget _buildSentLikesTab() {
    if (_sentLikes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'まだいいねを送っていません',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '素敵な人を見つけて、いいねを送ってみましょう！',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLikes,
      child: ListView.builder(
        itemCount: _sentLikes.length,
        itemBuilder: (context, index) {
          final like = _sentLikes[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(
                radius: 30,
                backgroundImage: like['image_url'] != null
                    ? NetworkImage(like['image_url'])
                    : null,
                child: like['image_url'] == null
                    ? const Icon(Icons.person, size: 30)
                    : null,
              ),
              title: Text(
                like['name'] ?? '名前未設定',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${like['age'] ?? '?'}歳 • ${like['gender'] ?? '未設定'}'),
                  if (like['liked_at'] != null)
                    Text(
                      'いいね送信: ${_formatDate(like['liked_at'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              trailing: const Icon(
                Icons.favorite,
                color: Colors.pink,
                size: 24,
              ),
              onTap: () {
                // プロフィール画面に遷移
                final userId = like['liked_user_id']?.toString() ?? 
                             like['user_id']?.toString() ?? 
                             like['uid']?.toString() ?? 
                             like['id']?.toString();
                
                if (userId != null && userId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(
                        userId: userId,
                      ),
                    ),
                  );
                } else {
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildReceivedLikesTab() {
    if (_receivedLikes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'まだいいねをもらっていません',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'プロフィールを充実させて、いいねをもらいましょう！',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLikes,
      child: ListView.builder(
        itemCount: _receivedLikes.length,
        itemBuilder: (context, index) {
          final like = _receivedLikes[index];
          
          // 24時間以内の新しいいいねかチェック
          final likedAt = DateTime.tryParse(like['liked_at'] ?? '');
          final isNewLike = likedAt != null && 
              DateTime.now().difference(likedAt).inHours < 24;
          
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: isNewLike ? 8 : 2,
            shadowColor: isNewLike ? Colors.pink.withOpacity(0.3) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isNewLike 
                  ? BorderSide(color: Colors.pink.withOpacity(0.5), width: 2)
                  : BorderSide.none,
            ),
            child: Container(
              decoration: isNewLike 
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          Colors.pink.withOpacity(0.05),
                          Colors.white,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    )
                  : null,
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: isNewLike 
                            ? Border.all(color: Colors.pink, width: 2)
                            : null,
                        boxShadow: isNewLike 
                            ? [
                                BoxShadow(
                                  color: Colors.pink.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundImage: like['image_url'] != null
                            ? NetworkImage(like['image_url'])
                            : null,
                        child: like['image_url'] == null
                            ? const Icon(Icons.person, size: 30)
                            : null,
                      ),
                    ),
                    // NEW バッジ
                    if (isNewLike)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.pink,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  like['name'] ?? '名前未設定',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isNewLike ? Colors.pink[700] : null,
                  ),
                ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${like['age'] ?? '?'}歳 • ${like['gender'] ?? '未設定'}'),
                  if (like['liked_at'] != null)
                    Text(
                      'いいね受信: ${_formatDate(like['liked_at'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              onTap: () {
                // プロフィール画面に遷移
                final userId = like['user_id']?.toString() ?? 
                             like['uid']?.toString() ?? 
                             like['id']?.toString() ?? 
                             like['liker_id']?.toString() ??
                             like['sender_id']?.toString();
                
                if (userId != null && userId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(
                        userId: userId,
                      ),
                    ),
                  );
                } else {
                }
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 受信バッジ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.pink[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite, color: Colors.pink, size: 14),
                        SizedBox(width: 4),
                        Text('受信', style: TextStyle(color: Colors.pink, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // いいねボタン
                  GestureDetector(
                    onTap: () {
                      // 複数のフィールドからユーザーIDを取得を試行
                      final userId = like['user_id']?.toString() ?? 
                                   like['uid']?.toString() ?? 
                                   like['id']?.toString() ?? 
                                   like['liker_id']?.toString() ??
                                   like['sender_id']?.toString();
                      
                      
                      if (userId != null && userId.isNotEmpty) {
                        final isLiked = _likedUsers.contains(userId);
                        _toggleUserLike(userId, isLiked);
                      } else {
                      }
                    },
                    child: Builder(
                      builder: (context) {
                        final userId = like['user_id']?.toString() ?? 
                                     like['uid']?.toString() ?? 
                                     like['id']?.toString() ?? 
                                     like['liker_id']?.toString() ??
                                     like['sender_id']?.toString();
                        final isLiked = userId != null ? _likedUsers.contains(userId) : false;
                        
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isLiked ? Colors.pink : Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.favorite,
                            color: isLiked ? Colors.white : Colors.grey[600],
                            size: 20,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    
    String? dateStr;
    if (dateValue is String) {
      dateStr = dateValue;
    } else if (dateValue is Map && dateValue.containsKey('liked_at')) {
      dateStr = dateValue['liked_at']?.toString();
    } else {
      dateStr = dateValue.toString();
    }
    
    if (dateStr == null || dateStr.isEmpty) return '';
    
    try {
      final DateTime date = DateTime.parse(dateStr).toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}日前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}時間前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分前';
      } else {
        return 'たった今';
      }
    } catch (e) {
      return '';
    }
  }

  /// Web版対応の画像表示ウィジェット
  Widget _buildWebSafeImage({
    required String? imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
    IconData fallbackIcon = Icons.restaurant,
    double fallbackIconSize = 40,
    Color? backgroundColor,
  }) {
    final container = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey[200],
        borderRadius: borderRadius,
      ),
      child: Icon(
        fallbackIcon,
        size: fallbackIconSize,
        color: Colors.grey[400],
      ),
    );

    // 画像URLがない場合はプレースホルダーを表示
    if (imageUrl == null || imageUrl.isEmpty) {
      return container;
    }

    return WebImageHelper.buildImage(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      errorWidget: container,
    );
  }

  /// レストラン画像専用のWeb対応表示ウィジェット
  Widget _buildRestaurantImage({
    required String? imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
  }) {
    return _buildWebSafeImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      fallbackIcon: Icons.restaurant,
      fallbackIconSize: width * 0.3,
    );
  }

  /// ユーザー画像専用のWeb対応表示ウィジェット
  Widget _buildUserImage({
    required String? imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
  }) {
    return _buildWebSafeImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      fallbackIcon: Icons.person,
      fallbackIconSize: width * 0.4,
    );
  }
}

