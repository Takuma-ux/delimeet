import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase追加
import '../services/auth_service.dart';
import '../services/web_image_helper.dart';
import 'map_search_page.dart';
import 'web_map_search_page.dart'; // Web版軽量地図ページ
import 'group_list_page.dart';
import 'restaurant_search_page.dart';
import 'profile_view_page.dart';
import 'user_search_page.dart';
import 'group_search_page.dart';
import 'account_page.dart';
import 'package:intl/intl.dart';
import 'restaurant_detail_page.dart'; // レストラン詳細ページを追加
import '../models/restaurant_model.dart'; // Restaurantクラスのインポートを修正

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  List<dynamic> _recommendedUsers = [];
  List<dynamic> _recommendedRestaurants = [];
  List<dynamic> _similarTasteUsers = [];
  bool _isLoading = true;
  bool _isLoadingRecommendations = false;
  Set<String> _likedUsers = {};
  Set<String> _likedRestaurants = {};
  List<String> _userFavoriteCategories = [];
  String _selectedAlgorithm = 'basic';  // レストランおすすめアルゴリズム選択
  String _algorithmDescription = '';  // アルゴリズムの説明
  String? _accountStatus; // 追加: アカウント状態

  // 自分の情報（プライバシー機能用）
  String? _myUserId;
  String? _mySchoolId;

  // Supabaseクライアント
  late final SupabaseClient _supabase;
  
  // 画像キャッシュ最適化
  static final Map<String, String> _thumbnailCache = {};
  static const int _maxThumbnailCache = 100;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    try {
      _initializeData();
    } catch (e, stackTrace) {
      // エラーハンドリング
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 画面が再表示される際にアカウント状態を最新に更新
    _loadUserProfile();
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = false; // まず画面を表示
    });

    try {
      // 並行してデータを取得（タイムアウトを適切に設定）
      final results = await Future.wait([
        _getRecommendedUsersFromSupabase().timeout(
          Duration(seconds: kIsWeb ? 5 : 3),
          onTimeout: () => <Map<String, dynamic>>[],
        ),
        _getRecommendedRestaurantsFromSupabase().timeout(
          Duration(seconds: kIsWeb ? 5 : 3),
          onTimeout: () => <Map<String, dynamic>>[],
        ),
      ], eagerError: false);

      if (mounted) {
        setState(() {
          _recommendedUsers = results[0] ?? [];
          _recommendedRestaurants = results[1] ?? [];
          _similarTasteUsers = [];
        });
      }

      // その他のデータをバックグラウンドで読み込み
      _loadAdditionalDataInBackground();
      
    } catch (e, stackTrace) {
      print('初期化エラー: $e');
      if (mounted) {
        setState(() {
          _recommendedUsers = [];
          _recommendedRestaurants = [];
          _similarTasteUsers = [];
        });
      }
    }
  }

  // 追加データの背景読み込み（Web版軽量化）
  Future<void> _loadAdditionalDataInBackground() async {
    try {
      if (kIsWeb) {
        // Web版では最小限の処理のみ
        await Future.wait([
          _loadUserLikes(),
          _loadUserProfile(),
        ], eagerError: false).timeout(const Duration(seconds: 2));
      } else {
        // モバイル版では全ての処理
        final additionalFutures = <Future<void>>[];
        additionalFutures.add(_loadUserLikes());
        additionalFutures.add(_loadUserProfile());
        additionalFutures.add(_loadSimilarTasteUsers());
        
        await Future.wait(additionalFutures, eagerError: false)
            .timeout(const Duration(seconds: 3));
      }
              
        // キャッシュに保存（削除済み）
      
    } catch (e) {
      // エラーハンドリング
    }
  }

  // リフレッシュ時のデータ更新（キャッシュクリア付き）
      Future<void> _refreshData() async {
      // キャッシュをクリア（削除済み）
    
    // 全データを再取得
    await _initializeData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('探す'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
            onPressed: _refreshData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // ローディング中の場合はローディング表示
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // アカウント状態が未取得の場合は、デフォルトで通常UIを表示
    // （_accountStatusがnullでも通常の機能は利用可能）
    if (_accountStatus == 'deactivated') {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'アカウントが停止中です',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'アカウントを復元しないとこの機能は利用できません。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // アカウント画面に遷移
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AccountPage(),
                      ),
                    );
                  },
                  child: const Text('アカウントを復元する'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    else {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // メインボタン（常に表示）
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMainButton(
                        icon: Icons.restaurant,
                        label: 'レストランを探す',
                        color: Colors.pink[400],
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RestaurantSearchPage(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMainButton(
                        icon: Icons.person,
                        label: 'ユーザーを探す',
                        color: Colors.blue[400],
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UserSearchPage(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              ],
            ),

            // おすすめユーザー
            if (_recommendedUsers.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionTitle('おすすめのユーザー'),
              const SizedBox(height: 12),
              SizedBox(
                height: 200, // 高さを統一
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recommendedUsers.length,
                  itemBuilder: (context, index) {
                    try {
                      return _buildUserCard(_recommendedUsers[index]);
                    } catch (e) {
                      return _buildErrorCard();
                    }
                  },
                ),
              ),
            ],

            // 同じレストランが好きな人
            if (_similarTasteUsers.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.restaurant_menu, color: Colors.orange[600], size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSectionTitle('同じレストランが好きな人'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Text(
                  'あなたと同じレストランをいいねした人たちです',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200, // 高さを統一
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _similarTasteUsers.length,
                  itemBuilder: (context, index) {
                    try {
                      return _buildSimilarTasteUserCard(_similarTasteUsers[index]);
                    } catch (e) {
                      return _buildErrorCard();
                    }
                  },
                ),
              ),
            ],

            // おすすめレストラン（データがある場合のみ表示）
            if (_recommendedRestaurants.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildRestaurantSectionHeader(),
              const SizedBox(height: 12),
              if (_algorithmDescription.isNotEmpty && _selectedAlgorithm == 'date_success') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(
                    _algorithmDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 220, // カードの高さに合わせて調整
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recommendedRestaurants.length,
                  itemBuilder: (context, index) {
                    try {
                      return _buildRestaurantCard(_recommendedRestaurants[index]);
                    } catch (e) {
                      return _buildErrorCard();
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }
  }

  Widget _buildMainButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
    bool isFullWidth = false,
  }) {
    return SizedBox(
      height: 120,
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? Colors.pink[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // 推薦理由に基づくバッジの色を取得
  Color _getRecommendationBadgeColor(Map<String, dynamic> user) {
    final String recommendationType = user['recommendation_type']?.toString() ?? '';
    if (recommendationType == 'same_restaurant') {
      return Colors.orange[600]!;
    } else if (recommendationType == 'same_category') {
      return Colors.blue[600]!;
    } else {
      return Colors.grey[600]!;
    }
  }

  // 推薦理由に基づくバッジのテキストを取得
  String _getRecommendationBadgeText(Map<String, dynamic> user) {
    final String recommendationType = user['recommendation_type']?.toString() ?? '';
    final int commonCount = user['common_restaurants_count'] ?? 0;
    
    if (recommendationType == 'same_restaurant') {
      return '共通${commonCount}店';
    } else if (recommendationType == 'same_category') {
      return '共通カテゴリ';
    } else {
      return '共通${commonCount}店';
    }
  }

  // 推薦理由に基づくタグの色を取得
  Color _getRecommendationTagColor(Map<String, dynamic> user) {
    final String recommendationType = user['recommendation_type']?.toString() ?? '';
    if (recommendationType == 'same_restaurant') {
      return Colors.orange[100]!;
    } else if (recommendationType == 'same_category') {
      return Colors.blue[100]!;
    } else {
      return Colors.grey[100]!;
    }
  }

  // 推薦理由に基づくタグのテキストを取得
  String _getRecommendationTagText(Map<String, dynamic> user) {
    final String recommendationType = user['recommendation_type']?.toString() ?? '';
    if (recommendationType == 'same_restaurant') {
      return 'レストラン共通';
    } else if (recommendationType == 'same_category') {
      return 'カテゴリ共通';
    } else {
      return '好みが似ています';
    }
  }

  // 推薦理由に基づくタグのテキスト色を取得
  Color _getRecommendationTagTextColor(Map<String, dynamic> user) {
    final String recommendationType = user['recommendation_type']?.toString() ?? '';
    if (recommendationType == 'same_restaurant') {
      return Colors.orange[700]!;
    } else if (recommendationType == 'same_category') {
      return Colors.blue[700]!;
    } else {
      return Colors.grey[700]!;
    }
  }

  Widget _buildRestaurantSectionHeader() {
    return Row(
      children: [
        Expanded(
          child: _buildSectionTitle('おすすめのレストラン'),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: DropdownButton<String>(
            value: _selectedAlgorithm,
            items: const [
              DropdownMenuItem(value: 'basic', child: Text('基本')),
              // DropdownMenuItem(value: 'collaborative', child: Text('協調')), // 十分なユーザーデータが蓄積されるまで一時的に非表示
              DropdownMenuItem(value: 'date_success', child: Text('成功率')),
            ],
            onChanged: (String? newValue) {
              if (newValue != null && newValue != _selectedAlgorithm) {
                _loadRecommendationsWithAlgorithm(newValue);
              }
            },
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue[700],
            ),
            underline: const SizedBox(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: 140, // 統一された幅
      height: 120, // 統一された高さ（160→120）
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(height: 4),
            Text(
              'エラー',
              style: TextStyle(
                fontSize: 10,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    try {
      final String? userId = user['id']?.toString();
      final bool isLiked = userId != null && _likedUsers.contains(userId);
      final String? imageUrl = user['image_url'] ?? user['photo_url'];
      final String name = user['name']?.toString() ?? '名前未設定';
      final String age = user['age']?.toString() ?? '';
      final String occupation = user['occupation']?.toString() ?? '';

      // サムネイル画像URLを生成（高速化）
      final optimizedImageUrl = imageUrl != null && imageUrl.isNotEmpty
          ? _getThumbnailUrl(imageUrl, width: 140, height: 120)
          : null;
      
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (userId != null && userId.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileViewPage(
                    userId: userId,
                  ),
                ),
              );
            }
          },
          child: Container(
            width: 150, // 幅を増やして余裕を持たせる
            height: 200, // 統一された高さ
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 画像部分（固定高さ）
                Container(
                  width: 150, // カードと同じ幅
                  height: 120, // 固定高さ
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: optimizedImageUrl != null
                      ? ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: WebImageHelper.buildImage(
                            optimizedImageUrl,
                            width: 150,
                            height: 120,
                            fit: BoxFit.cover,
                            errorWidget: Container(
                              width: 150,
                              height: 120,
                              color: Colors.grey[200],
                              child: const Icon(Icons.person, size: 40, color: Colors.grey),
                            ),
                          ),
                        )
                      : const Icon(Icons.person, size: 40, color: Colors.grey),
                ),
                // テキスト部分（固定高さ）
                Container(
                  width: 150,
                  height: 80, // 固定高さ
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          // 左の空きスペース
                          if (userId != null) 
                            const SizedBox(width: 30) // いいねボタンと同じ幅
                          else
                            const Expanded(child: SizedBox()),
                          
                          // 中央の名前
                          Expanded(
                            flex: 2,
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          
                          // 右のいいねボタン
                          if (userId != null) 
                            SizedBox(
                              width: 30,
                              child: GestureDetector(
                                onTap: () => _toggleUserLike(userId, isLiked),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isLiked ? Icons.favorite : Icons.favorite_border,
                                    color: isLiked ? Colors.red : Colors.grey,
                                    size: 18,
                                  ),
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 30), // 右側の余白
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (age.isNotEmpty || occupation.isNotEmpty)
                        Text(
                          [age.isNotEmpty ? '${age}歳' : '', occupation]
                              .where((s) => s.isNotEmpty)
                              .join(' • '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      return _buildErrorCard();
    }
  }

  Widget _buildRestaurantCard(Map<String, dynamic> restaurant) {
    try {
      // 複数のIDフィールドを確認
      final String? restaurantId = restaurant['id']?.toString() ?? 
                                  restaurant['restaurant_id']?.toString() ?? 
                                  restaurant['hotpepper_id']?.toString() ?? 
                                  restaurant['shop_id']?.toString();
      final bool isLiked = restaurantId != null && _likedRestaurants.contains(restaurantId);
      final String? imageUrl = restaurant['image_url'];
      final String name = restaurant['name']?.toString() ?? '店名未設定';
      final String category = restaurant['category']?.toString() ?? '';
      final String priceRange = restaurant['price_range']?.toString() ?? '';
      final String nearestStation = restaurant['nearest_station']?.toString() ?? '';

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (restaurantId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RestaurantDetailPage(
                    restaurant: Restaurant(
                      id: restaurantId,
                      name: name,
                      category: category,
                      priceRange: priceRange,
                      nearestStation: nearestStation,
                      imageUrl: imageUrl,
                      prefecture: restaurant['prefecture']?.toString(),
                      hotpepperUrl: restaurant['hotpepper_url']?.toString(),
                    ),
                  ),
                ),
              );
            }
          },
          child: Container(
            width: 140, // 統一された幅
            height: 200, // 高さを元に戻す（190→200）
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    // 画像部分（固定高さ）
                    Container(
                      width: 140, // カードと同じ幅
                      height: 100, // 高さを再調整（110→100）
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: WebImageHelper.buildImage(
                                imageUrl,
                                width: 140,
                                height: 100,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  width: 140,
                                  height: 100,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
                                ),
                              ),
                            )
                          : Container(
                              width: 140,
                              height: 100,
                              color: Colors.grey[200],
                              child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
                            ),
                    ),
                    // テキスト部分（固定高さ）
                    Container(
                      width: 140,
                      height: 100, // 高さを拡張（80→100）
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 店名
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // カテゴリ・価格帯
                          if (category.isNotEmpty || priceRange.isNotEmpty)
                            Text(
                              [category, priceRange]
                                  .where((s) => s.isNotEmpty)
                                  .join(' • '),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 2),
                          // 駅情報
                          if (nearestStation.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.train,
                                    size: 10,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      nearestStation,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                // 右下にいいねボタン（常に表示）
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (restaurant['hotpepper_url'] != null && restaurant['hotpepper_url'].toString().isNotEmpty)
                        GestureDetector(
                          onTap: () => _openHotpepperUrl(restaurant['hotpepper_url'].toString()),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.more_horiz,
                              color: Colors.grey,
                              size: 18,
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () {
                          if (restaurantId != null) {
                            _toggleRestaurantLike(restaurantId, isLiked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? Colors.red : Colors.grey,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      return _buildErrorCard();
    }
  }

  // 新しいレストランおすすめAPI（アルゴリズム選択可能）
  Future<void> _loadRecommendationsWithAlgorithm(String algorithm) async {
    setState(() => _isLoadingRecommendations = true);
    
    final functions = FirebaseFunctions.instanceFor(
      region: 'us-central1',
      app: Firebase.app(),
    );
    final callable = functions.httpsCallable('getRestaurantRecommendations');
    
    try {
      final result = await callable({
        'algorithm': algorithm,
        'limit': 8, // 取得件数を削減
      }).timeout(const Duration(seconds: 3)); // タイムアウト短縮

      if (mounted && result.data is Map<String, dynamic>) {
        final Map<String, dynamic> data = result.data as Map<String, dynamic>;
        
        setState(() {
          _recommendedRestaurants = List<Map<String, dynamic>>.from(
            (data['restaurants'] as List<dynamic>? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
          );
          _algorithmDescription = data['description']?.toString() ?? '';
          _selectedAlgorithm = algorithm;
        });
      }
    } catch (e) {
      
      // 協調アルゴリズムでエラーが発生した場合は基本アルゴリズムにフォールバック
      // 注意：協調フィルタリングは現在無効化されているため、このケースは発生しないはずです
      if (algorithm == 'collaborative') {
        try {
          final fallbackResult = await callable({
            'algorithm': 'basic',
            'limit': 8,
          }).timeout(const Duration(seconds: 5));

          if (mounted && fallbackResult.data is Map<String, dynamic>) {
            final Map<String, dynamic> fallbackData = fallbackResult.data as Map<String, dynamic>;
            
            setState(() {
              _recommendedRestaurants = List<Map<String, dynamic>>.from(
                (fallbackData['restaurants'] as List<dynamic>? ?? [])
                    .map((item) => Map<String, dynamic>.from(item as Map))
              );
              _algorithmDescription = '協調フィルタリングでエラーが発生したため、基本推薦を表示しています';
              _selectedAlgorithm = algorithm; // 元のアルゴリズムを維持
            });
            
          }
        } catch (fallbackError) {
          if (mounted) {
            setState(() {
              _recommendedRestaurants = [];
              _algorithmDescription = '協調フィルタリングでエラーが発生しました';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _recommendedRestaurants = [];
            _algorithmDescription = 'エラーが発生しました';
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecommendations = false);
      }
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final users = await _getRecommendedUsersForced();
      final restaurants = await _getRecommendedRestaurantsForced();
      
      if (mounted) {
        setState(() {
          _recommendedUsers = users;
          _recommendedRestaurants = restaurants;
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _recommendedUsers = [];
          _recommendedRestaurants = [];
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getRecommendedUsersForced() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return [];
      }

      
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomValue = DateTime.now().microsecondsSinceEpoch;
      final uniqueId = '${user.uid}_${timestamp}_${randomValue}';
      
      
      // Web版ではタイムアウトを短縮
      final timeout = kIsWeb ? const Duration(seconds: 3) : const Duration(seconds: 5);
      
      final callable = functions.httpsCallable(
        'getRecommendedUsers',
        options: HttpsCallableOptions(
          timeout: timeout,
        ),
      );
      
      
      final result = await callable.call({
        'userId': user.uid,
        'timestamp': timestamp,
        'randomValue': randomValue,
        'cacheBreaker': uniqueId,
        'forceRefresh': true,
        'requestId': uniqueId,
        'nocache': true,
        'limit': 6, // 取得件数を削減して高速化
      });
      
      
      if (result.data == null) {
        return [];
      }

      
      List<Map<String, dynamic>> users = [];
      
      if (result.data is List) {
        users = (result.data as List).map((user) {
          if (user is Map<String, dynamic>) {
            return user;
          } else if (user is Map) {
            return Map<String, dynamic>.fromEntries(
              user.entries.map((e) => MapEntry(e.key.toString(), e.value))
            );
          }
          return <String, dynamic>{};
        }).toList();
      }
      
      return users;
      
    } catch (e, stackTrace) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getRecommendedRestaurantsForced() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return [];
      }
      
      // 使用するカテゴリを決定
      List<String> categoriesToUse;
      bool isUsingDefaultCategories = false;
      
      if (_userFavoriteCategories.isEmpty) {
        // デフォルトカテゴリを使用（軽量化のため減らす）
        categoriesToUse = [
          '中華', 'ラーメン', 'イタリアン'
        ];
        isUsingDefaultCategories = true;
      } else {
        // ユーザーの好みカテゴリを使用（軽量化のため3個まで制限）
        categoriesToUse = _userFavoriteCategories.take(3).toList();
      }
      
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomValue = DateTime.now().microsecondsSinceEpoch;
      
      List<Map<String, dynamic>> allRestaurants = [];
      
      // カテゴリ数に応じて各カテゴリから取得するレストラン数を調整（軽量化）
      int restaurantsPerCategory = 2; // 固定で2件ずつ（最大6件）
      
      // 各カテゴリからレストランを取得
      for (String category in categoriesToUse) {
        final uniqueId = '${user.uid}_${category}_${timestamp}_${randomValue}';
        
        try {
          // レストラン検索関数を呼び出し
          // Web版ではタイムアウトを短縮
          final timeout = kIsWeb ? const Duration(seconds: 2) : const Duration(seconds: 3);
          
          final callable = functions.httpsCallable(
            'searchRestaurants',
            options: HttpsCallableOptions(
              timeout: timeout,
            ),
          );
          
          final result = await callable.call({
            'category': category,
            'userId': user.uid,
            'timestamp': timestamp,
            'randomValue': randomValue,
            'cacheBreaker': uniqueId,
            'forceRefresh': true,
            'requestId': uniqueId,
            'nocache': true,
            'limit': restaurantsPerCategory,
          });
          
          if (result.data is Map<String, dynamic>) {
            final Map<String, dynamic> data = result.data as Map<String, dynamic>;
            
            if (data.containsKey('restaurants') && data['restaurants'] is List) {
              final List<dynamic> restaurantList = data['restaurants'] as List<dynamic>;
              
              final List<Map<String, dynamic>> restaurants = restaurantList
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              
              // カテゴリ情報を追加
              for (var restaurant in restaurants) {
                restaurant['source_category'] = category;
                restaurant['is_default_category'] = isUsingDefaultCategories;
              }
              
              allRestaurants.addAll(restaurants);
            }
          } else if (result.data is List) {
            final List<dynamic> restaurantList = result.data as List<dynamic>;
            
            final List<Map<String, dynamic>> restaurants = restaurantList
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            
            // カテゴリ情報を追加
            for (var restaurant in restaurants) {
              restaurant['source_category'] = category;
              restaurant['is_default_category'] = isUsingDefaultCategories;
            }
            
            allRestaurants.addAll(restaurants);
          }
        } catch (e) {
        }
      }
      
      final categoryType = isUsingDefaultCategories ? 'デフォルト' : 'ユーザー選択';
      return allRestaurants;
      
    } catch (e, stackTrace) {
      return [];
    }
  }

  Future<void> _loadUserLikes() async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      final callable = functions.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 3)); // タイムアウト短縮
      
      if (mounted) {
        setState(() {
          _likedRestaurants = Set<String>.from(result.data['likedRestaurants'] ?? []);
          final sentLikes = List.from(result.data['sentLikes'] ?? []);
          
          // デバッグ: 最初の数件のいいねデータを出力
          if (sentLikes.isNotEmpty) {
            for (int i = 0; i < sentLikes.length && i < 3; i++) {
              final like = sentLikes[i];
            }
          }
          
          // 複数のIDフィールドを試行して、いいね状態を設定
          _likedUsers = {};
          for (final like in sentLikes) {
            final possibleIds = [
              like['liked_user_id']?.toString(),
              like['id']?.toString(),
              like['user_id']?.toString(),
            ].where((id) => id != null && id.isNotEmpty);
            
            for (final id in possibleIds) {
              _likedUsers.add(id!);
            }
          }
        });
      }
    } catch (e) {
    }
  }

  Future<void> _toggleUserLike(String userId, bool currentLikeState) async {
    if (!mounted) return;

    // 既にいいね済みの場合は取り消しできない
    if (currentLikeState) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('いいねは取り消すことができません'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _likedUsers.add(userId);
    });

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      final callable = functions.httpsCallable('addUserLike');
      await callable({'likedUserId': userId}).timeout(const Duration(seconds: 3)); // タイムアウト短縮
      
    } catch (e) {
      
      if (mounted) {
        setState(() {
          _likedUsers.remove(userId);
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

  Future<void> _toggleRestaurantLike(String restaurantId, bool currentLikeState) async {
    if (!mounted) return;

    setState(() {
      if (currentLikeState) {
        _likedRestaurants.remove(restaurantId);
      } else {
        _likedRestaurants.add(restaurantId);
      }
    });

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      final callable = functions.httpsCallable(
        currentLikeState ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      
      await callable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 5));
      
    } catch (e) {
      
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

  Future<void> _loadRecommendedUsersForced() async {
    try {
      final users = await _getRecommendedUsersForced();
      if (mounted) {
        setState(() {
          _recommendedUsers = users;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recommendedUsers = [];
        });
      }
    }
  }

  Future<void> _loadSimilarTasteUsers() async {
    // Web版では機能を無効化
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _similarTasteUsers = [];
        });
      }
      return;
    }
    
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      final callable = functions.httpsCallable('getUsersWithSimilarRestaurantLikes');
      final result = await callable({'limit': 5}).timeout(const Duration(seconds: 6));
      
      if (mounted) {
        setState(() {
          _similarTasteUsers = result.data['users'] ?? [];
        });
      }
    } catch (e) {
      // エラー時は空のリストを維持
    }
  }

  Widget _buildSimilarTasteUserCard(Map<String, dynamic> user) {
    try {
      final String? userId = user['user_id']?.toString() ?? user['id']?.toString();
      final bool isLiked = userId != null && _likedUsers.contains(userId);
      final String? imageUrl = user['image_url'];
      final String name = user['name']?.toString() ?? '名前未設定';
      final String age = user['age']?.toString() ?? '';
      final String occupation = user['occupation']?.toString() ?? '';
      final int commonCount = user['common_restaurants_count'] ?? 0;

      return GestureDetector(
        onTap: () {
          if (userId != null && userId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileViewPage(
                  userId: userId,
                ),
              ),
            );
          }
        },
        child: Container(
          width: 140, // 統一された幅
          height: 200, // 統一された高さ
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange[200]!, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 画像部分（固定高さ）
              Container(
                width: 140, // カードと同じ幅
                height: 100, // 少し小さく
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Stack(
                  children: [
                    // 画像またはプレースホルダー
                    Container(
                      width: 140,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        color: Colors.grey[200],
                      ),
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: WebImageHelper.buildImage(
                                imageUrl,
                                width: 140,
                                height: 100,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  width: 140,
                                  height: 100,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.person, size: 40, color: Colors.grey),
                                ),
                              ),
                            )
                          : const Icon(Icons.person, size: 40, color: Colors.grey),
                    ),
                    // いいねボタン
                    if (userId != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => _toggleUserLike(userId, isLiked),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? Colors.red : Colors.grey,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    // 共通レストラン数バッジ（推薦理由対応）
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getRecommendationBadgeColor(user),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _getRecommendationBadgeText(user),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // テキスト部分（固定高さ）
              Container(
                width: 140,
                height: 100, // 調整
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    if (age.isNotEmpty || occupation.isNotEmpty)
                      Text(
                        [age.isNotEmpty ? '${age}歳' : '', occupation]
                            .where((s) => s.isNotEmpty)
                            .join(' • '),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getRecommendationTagColor(user),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getRecommendationTagText(user),
                        style: TextStyle(
                          fontSize: 9,
                          color: _getRecommendationTagTextColor(user),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      return _buildErrorCard();
    }
  }

  /// ホットペッパーURLを開く
  Future<void> _openHotpepperUrl(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('URLを開けませんでした'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('営業時間の確認に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ユーザープロファイルを取得してカテゴリ情報を取得（Supabase使用）
  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Supabaseから直接ユーザープロファイルを取得
      final userResult = await _supabase
          .from('users')
          .select('id, favorite_categories, account_status, school_id')
          .eq('firebase_uid', user.uid)
          .maybeSingle();
      
      if (mounted && userResult != null) {
        final categories = userResult['favorite_categories'];
        final accountStatus = userResult['account_status']?.toString();
        final schoolId = userResult['school_id']?.toString();
        
        setState(() {
          _myUserId = userResult['id']?.toString();
          _mySchoolId = schoolId;
          if (categories is List && categories.isNotEmpty) {
            _userFavoriteCategories = categories.map((e) => e.toString()).toList();
          } else {
            _userFavoriteCategories = [];
          }
          _accountStatus = accountStatus;
        });
      } else {
        if (mounted) {
          setState(() {
            _myUserId = null;
            _mySchoolId = null;
            _userFavoriteCategories = [];
            _accountStatus = null;
          });
        }
      }
    } catch (e) {
      // エラー時は空配列を設定（デフォルトカテゴリ使用）
      if (mounted) {
        setState(() {
          _myUserId = null;
          _mySchoolId = null;
          _userFavoriteCategories = [];
          _accountStatus = null;
        });
      }
      print('🔍 _loadUserProfile エラー: $e');
    }
  }

  // Supabaseから直接ユーザー推薦を取得（絞り込み機能付き）
  Future<List<Map<String, dynamic>>> _getRecommendedUsersFromSupabase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No current user found');
        return [];
      }

      print('Current user UID: "' + user.uid + '"');

      // 現在のユーザーの詳細情報を取得（マッチング条件含む）
      final userResult = await _supabase
          .from('users')
          .select('id, firebase_uid, preferred_age_range, preferred_gender, payment_preference, gender, age')
          .eq('firebase_uid', user.uid)
          .maybeSingle();

      if (userResult != null) {
        print('DB firebase_uid: "' + (userResult['firebase_uid'] ?? '') + '"');
      }

      if (userResult == null) {
        print('No user found in Supabase');
        return [];
      }

      final userUuid = userResult['id'];
      final preferredAgeRange = userResult['preferred_age_range']?.toString();
      final preferredGender = userResult['preferred_gender']?.toString();
      final paymentPreference = userResult['payment_preference']?.toString();
      final currentUserGender = userResult['gender']?.toString();
      final currentUserAge = userResult['age'];


      // まず絞り込み条件で候補者を取得
      List<Map<String, dynamic>> filteredUsers = await _getFilteredUsers(
        userUuid, 
        preferredAgeRange, 
        preferredGender, 
        paymentPreference,
        currentUserGender,
        currentUserAge,
      );

      // プライバシー設定でフィルタリング
      final privacyFilteredUsers = filteredUsers.where((user) {
        // 身内バレ防止機能: 相手がhide_from_same_school = trueかつ同じ学校の場合は除外
        if (user['hide_from_same_school'] == true && 
            _mySchoolId != null && 
            user['school_id'] != null &&
            _mySchoolId == user['school_id']) {
          return false;
        }
        
        // いいね限定表示機能: 相手がvisible_only_if_liked = trueかつ自分がいいねしていない場合は除外
        if (user['visible_only_if_liked'] == true && 
            !_likedUsers.contains(user['id']?.toString())) {
          return false;
        }
        
        return true;
      }).toList();


      // 絞り込み結果が3未満の場合は既存の方法で補完
      if (privacyFilteredUsers.length < 3) {
        print('Filtered users count: ${privacyFilteredUsers.length}, falling back to basic recommendation');
        final basicUsers = await _getBasicRecommendedUsers(userUuid, 8 - privacyFilteredUsers.length);
        
        // 重複を避けて追加
        final existingIds = privacyFilteredUsers.map((u) => u['id']).toSet();
        for (final basicUser in basicUsers) {
          if (!existingIds.contains(basicUser['id'])) {
            privacyFilteredUsers.add(basicUser);
          }
        }
      }

      return privacyFilteredUsers.take(8).toList();
    } catch (e) {
      print('Supabase user recommendation error: $e');
      return [];
    }
  }

  // 絞り込み条件でユーザーを取得
  Future<List<Map<String, dynamic>>> _getFilteredUsers(
    String userUuid,
    String? preferredAgeRange,
    String? preferredGender,
    String? paymentPreference,
    String? currentUserGender,
    int? currentUserAge,
  ) async {
    try {
      var query = _supabase
          .from('users')
          .select('''
            id,
            name,
            age,
            occupation,
            image_url,
            prefecture,
            favorite_categories,
            created_at,
            gender,
            preferred_age_range,
            preferred_gender,
            payment_preference,
            school_id,
            school_type,
            hide_from_same_school,
            visible_only_if_liked
          ''')
          .neq('id', userUuid);

      // 希望性別でフィルタリング
      if (preferredGender != null && preferredGender.isNotEmpty && preferredGender != 'どちらでも') {
        query = query.eq('gender', preferredGender);
      }

      // 相手が自分の性別を希望しているかもフィルタリング
      if (currentUserGender != null && currentUserGender.isNotEmpty) {
        query = query.or('preferred_gender.eq.$currentUserGender,preferred_gender.eq.どちらでも,preferred_gender.is.null');
      }

      final candidates = await query.limit(50); // 多めに取得してから年齢と支払い条件で絞り込み

      // 年齢範囲でフィルタリング
      List<Map<String, dynamic>> ageFilteredUsers = [];
      if (preferredAgeRange != null && preferredAgeRange.isNotEmpty) {
        final ageRange = _parseAgeRange(preferredAgeRange);
        for (final candidate in candidates) {
          final age = candidate['age'];
          if (age != null && age >= ageRange['min']! && age <= ageRange['max']!) {
            // 相手も自分の年齢を希望範囲に含んでいるかチェック
            if (_isUserInTargetAgeRange(candidate, currentUserAge)) {
              ageFilteredUsers.add(candidate);
            }
          }
        }
      } else {
        // 年齢範囲の指定がない場合は年齢フィルタを適用しない
        for (final candidate in candidates) {
          if (_isUserInTargetAgeRange(candidate, currentUserAge)) {
            ageFilteredUsers.add(candidate);
          }
        }
      }

      // 支払い設定で優先順位を適用
      ageFilteredUsers.sort((a, b) => _compareByPaymentPreference(a, b, paymentPreference));

      return ageFilteredUsers;
    } catch (e) {
      print('Error in _getFilteredUsers: $e');
      return [];
    }
  }

  // 基本的な推薦ユーザー取得（フォールバック用）
  Future<List<Map<String, dynamic>>> _getBasicRecommendedUsers(String userUuid, int limit) async {
    try {
      final result = await _supabase
          .from('users')
          .select('''
            id,
            name,
            age,
            occupation,
            image_url,
            prefecture,
            favorite_categories,
            created_at,
            gender,
            preferred_age_range,
            preferred_gender,
            payment_preference,
            school_id,
            school_type,
            hide_from_same_school,
            visible_only_if_liked
          ''')
          .neq('id', userUuid)
          .order('created_at', ascending: false)
          .limit(limit);

      // プライバシー設定でフィルタリング
      final filteredResult = result.where((user) {
        // 身内バレ防止機能: 相手がhide_from_same_school = trueかつ同じ学校の場合は除外
        if (user['hide_from_same_school'] == true && 
            _mySchoolId != null && 
            user['school_id'] != null &&
            _mySchoolId == user['school_id']) {
          return false;
        }
        
        // いいね限定表示機能: 相手がvisible_only_if_liked = trueかつ自分がいいねしていない場合は除外
        if (user['visible_only_if_liked'] == true && 
            !_likedUsers.contains(user['id']?.toString())) {
          return false;
        }
        
        return true;
      }).toList();

      return List<Map<String, dynamic>>.from(filteredResult);
    } catch (e) {
      print('Error in _getBasicRecommendedUsers: $e');
      return [];
    }
  }

  // 年齢範囲をパース
  Map<String, int> _parseAgeRange(String ageRange) {
    switch (ageRange) {
      case '18-25':
        return {'min': 18, 'max': 25};
      case '26-35':
        return {'min': 26, 'max': 35};
      case '36-45':
        return {'min': 36, 'max': 45};
      case '46-55':
        return {'min': 46, 'max': 55};
      case '56+':
        return {'min': 56, 'max': 100};
      default:
        return {'min': 18, 'max': 100};
    }
  }

  // 相手が自分の年齢を希望範囲に含んでいるかチェック
  bool _isUserInTargetAgeRange(Map<String, dynamic> candidate, int? currentUserAge) {
    if (currentUserAge == null) return true;
    
    final candidatePreferredAgeRange = candidate['preferred_age_range']?.toString();
    if (candidatePreferredAgeRange == null || candidatePreferredAgeRange.isEmpty) {
      return true; // 相手に年齢希望がない場合は含める
    }

    final ageRange = _parseAgeRange(candidatePreferredAgeRange);
    return currentUserAge >= ageRange['min']! && currentUserAge <= ageRange['max']!;
  }

  // 支払い設定による優先順位比較
  int _compareByPaymentPreference(Map<String, dynamic> a, Map<String, dynamic> b, String? userPaymentPreference) {
    final aPayment = a['payment_preference']?.toString() ?? '';
    final bPayment = b['payment_preference']?.toString() ?? '';

    if (userPaymentPreference == null || userPaymentPreference.isEmpty) {
      return 0; // 順序変更なし
    }

    int getPaymentPriority(String candidatePayment, String userPref) {
      switch (userPref) {
        case 'pay': // 奢りたい人
          if (candidatePayment == 'be_paid') return 1; // 奢られたい人を最優先
          if (candidatePayment == 'split') return 2; // 割り勘希望を次
          if (candidatePayment == 'pay') return 3; // 同じ奢りたい人を最後
          return 4; // 未設定
        case 'be_paid': // 奢られたい人
          if (candidatePayment == 'pay') return 1; // 奢りたい人を最優先
          if (candidatePayment == 'split') return 2; // 割り勘希望を次
          if (candidatePayment == 'be_paid') return 3; // 同じ奢られたい人を最後
          return 4; // 未設定
        case 'split': // 割り勘希望
          if (candidatePayment == 'split') return 1; // 同じ割り勘希望を最優先
          if (candidatePayment == 'pay') return 2; // 奢りたい人を次
          if (candidatePayment == 'be_paid') return 3; // 奢られたい人を次
          return 4; // 未設定
        default:
          return 4;
      }
    }

    final aPriority = getPaymentPriority(aPayment, userPaymentPreference);
    final bPriority = getPaymentPriority(bPayment, userPaymentPreference);

    return aPriority.compareTo(bPriority);
  }

  // Supabaseから直接レストラン推薦を取得（高速化）
  Future<List<Map<String, dynamic>>> _getRecommendedRestaurantsFromSupabase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      // ユーザーの好みカテゴリを取得（single()の代わりにmaybeSingle()を使用）
      final userResult = await _supabase
          .from('users')
          .select('favorite_categories, prefecture')
          .eq('firebase_uid', user.uid)
          .maybeSingle();

      List<String> categories = [];
      if (userResult != null && userResult['favorite_categories'] != null) {
        categories = List<String>.from(userResult['favorite_categories']);
      }

      // デフォルトカテゴリ
      if (categories.isEmpty) {
        categories = ['中華', 'ラーメン', 'イタリアン'];
      }

      // レストラン推薦クエリ（インデックス活用）
      final categoryFilter = categories.take(3).map((e) => '"$e"').join(',');
      final result = await _supabase
          .from('restaurants')
          .select('''
            id,
            name,
            category,
            prefecture,
            nearest_station,
            price_range,
            low_price,
            high_price,
            image_url,
            hotpepper_url,
            operating_hours
          ''')
          .filter('category', 'in', '($categoryFilter)')
          .order('created_at', ascending: false)
          .limit(6);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Supabase restaurant recommendation error: $e');
      return [];
    }
  }

  // サムネイル画像URLを生成（Firebase Storage最適化）
  String _getThumbnailUrl(String originalUrl, {int width = 200, int height = 200}) {
    if (!originalUrl.contains('firebasestorage.googleapis.com')) {
      return originalUrl;
    }
    if (kIsWeb) {
      return originalUrl; // Webはそのまま
    }
    // サムネイル生成
    final cacheKey = ' {originalUrl}_${width}x${height}';
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey]!;
    }
    final thumbnailUrl = '$originalUrl?alt=media&w=$width&h=$height&fit=crop';
    if (_thumbnailCache.length >= _maxThumbnailCache) {
      final keysToRemove = _thumbnailCache.keys.take(_maxThumbnailCache ~/ 2).toList();
      for (final key in keysToRemove) {
        _thumbnailCache.remove(key);
      }
    }
    _thumbnailCache[cacheKey] = thumbnailUrl;
    return thumbnailUrl;
  }

  // Web版で無効化されたボタンを表示
  Widget _buildDisabledButton({
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: Colors.grey[500]),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
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