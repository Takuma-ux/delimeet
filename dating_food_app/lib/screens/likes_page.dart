import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_view_page.dart';
import 'restaurant_detail_page.dart';
import '../services/web_image_helper.dart';
import '../models/restaurant_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LikesPage extends StatefulWidget {
  const LikesPage({super.key});

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _sentLikes = [];
  List<dynamic> _receivedLikes = [];
  List<dynamic> _likedRestaurants = [];
  Set<String> _currentLikedRestaurants = {};
  bool _isLoading = true;

  // キャッシュキー
  static const String _sentLikesKey = 'likes_sent_cache';
  static const String _receivedLikesKey = 'likes_received_cache';
  static const String _likedRestaurantsKey = 'likes_restaurants_cache';
  static const String _cacheTimeKey = 'likes_cache_time';
  static const Duration _cacheValidDuration = Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLikesFromCache();
  }

  Future<void> _loadLikesFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final sentJson = prefs.getString(_sentLikesKey);
    final receivedJson = prefs.getString(_receivedLikesKey);
    final restJson = prefs.getString(_likedRestaurantsKey);
    final cacheTime = prefs.getInt(_cacheTimeKey);
    bool loadedFromCache = false;
    if (sentJson != null && receivedJson != null && restJson != null && cacheTime != null) {
      final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
      if (DateTime.now().difference(cacheDateTime) < _cacheValidDuration) {
        try {
          final sent = jsonDecode(sentJson);
          final received = jsonDecode(receivedJson);
          final rest = jsonDecode(restJson);
          setState(() {
            _sentLikes = sent;
            _receivedLikes = received;
            _likedRestaurants = rest;
            _currentLikedRestaurants = rest
                .map<String>((restaurant) => restaurant['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toSet();
            _isLoading = false;
          });
          loadedFromCache = true;
        } catch (e) {}
      }
    }
    if (!loadedFromCache) {
      setState(() {
        _isLoading = true;
      });
      await _initializeData(forceRefresh: true);
    }
  }

  Future<void> _saveLikesToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sentLikesKey, jsonEncode(_sentLikes));
    await prefs.setString(_receivedLikesKey, jsonEncode(_receivedLikes));
    await prefs.setString(_likedRestaurantsKey, jsonEncode(_likedRestaurants));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _initializeData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      await Future.wait([
        _loadLikesData(),
        _loadLikedRestaurants(),
      ], eagerError: false);
      await _saveLikesToCache();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadLikesData() async {
    if (!mounted) return;

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 10));
      
      if (mounted) {
        setState(() {
          _sentLikes = result.data['sentLikes'] ?? [];
          _receivedLikes = result.data['receivedLikes'] ?? [];
          
          // 日付順（新しい順）に並び替え
          _sentLikes.sort((a, b) {
            final dateA = a['liked_at'];
            final dateB = b['liked_at'];
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return DateTime.parse(dateB).compareTo(DateTime.parse(dateA));
          });
          
          _receivedLikes.sort((a, b) {
            final dateA = a['liked_at'];
            final dateB = b['liked_at'];
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return DateTime.parse(dateB).compareTo(DateTime.parse(dateA));
          });
        });
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _sentLikes = [];
          _receivedLikes = [];
        });
      }
    }
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
      await _loadLikesData();
      await _saveLikesToCache();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadLikedRestaurants() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('getUserFavoriteRestaurants');
      final result = await callable().timeout(const Duration(seconds: 10));
      
      
      // success フィールドがある場合はチェック、ない場合は直接restaurantsを取得
      final bool isSuccess = result.data['success'] == true || result.data['restaurants'] != null;
      
      if (isSuccess && mounted) {
        setState(() {
          _likedRestaurants = result.data['restaurants'] ?? [];
          _currentLikedRestaurants = _likedRestaurants
              .map((restaurant) => restaurant['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
        });
        await _saveLikesToCache();
      } else {
        // レスポンスが期待した形式でない場合は空配列をセット
        if (mounted) {
          setState(() {
            _likedRestaurants = [];
            _currentLikedRestaurants = {};
          });
        }
      }
    } catch (e) {
      
      // エラー時も空配列をセットしてタブが正常に表示されるようにする
      if (mounted) {
        setState(() {
          _likedRestaurants = [];
          _currentLikedRestaurants = {};
        });
      }
      
      // エラー時もログを詳細に出力
      if (e.toString().contains('TimeoutException')) {
      } else if (e.toString().contains('internal')) {
      }
    }
  }

  Future<void> _toggleRestaurantLike(String restaurantId, bool currentLikeState) async {
    if (!mounted) return;

    // 即座にUIを更新（楽観的更新）
    setState(() {
      if (currentLikeState) {
        _currentLikedRestaurants.remove(restaurantId);
      } else {
        _currentLikedRestaurants.add(restaurantId);
      }
    });

    // バックグラウンドでAPI呼び出し
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        currentLikeState ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      
      await callable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 5));
      
      
      // いいね解除の場合のみお気に入りリストを再読み込み
      if (currentLikeState) {
        _loadLikedRestaurants();
      }
    } catch (e) {
      
      // エラー時のみUIを元に戻す
      if (mounted) {
        setState(() {
          if (currentLikeState) {
            _currentLikedRestaurants.add(restaurantId);
          } else {
            _currentLikedRestaurants.remove(restaurantId);
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

  String _formatPriceRange(dynamic restaurant) {
    // low_price と high_price を優先的に使用
    final lowPrice = restaurant['low_price'];
    final highPrice = restaurant['high_price'];
    
    if (lowPrice != null && highPrice != null) {
      return '${lowPrice}〜${highPrice}円';
    } else if (lowPrice != null) {
      return '${lowPrice}円〜';
    } else if (highPrice != null) {
      return '〜${highPrice}円';
    }
    
    // フォールバック: price_range文字列を使用
    final priceRange = restaurant['price_range'];
    return priceRange?.toString() ?? '価格不明';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    
    try {
      final DateTime date = DateTime.parse(dateString);
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final DateTime yesterday = today.subtract(const Duration(days: 1));
      final DateTime messageDate = DateTime(date.year, date.month, date.day);
      
      if (messageDate == today) {
        return '今日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (messageDate == yesterday) {
        return '昨日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.month}/${date.day}';
      }
    } catch (e) {
      return '';
    }
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
            Tab(text: 'いいね受信'),
            Tab(text: 'いいね送信'),
            Tab(text: 'レストラン'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              _loadLikes();
              _loadLikedRestaurants();
            },
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
                _buildReceivedLikesTab(),
                _buildSentLikesTab(),
                _buildRestaurantsTab(),
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
              onTap: () {
                // 複数のIDフィールドを確認してユーザーIDを取得
                final userId = like['liked_user_id'] ?? 
                              like['receiver_id'] ?? 
                              like['id'] ?? 
                              like['user_id'] ?? 
                              like['firebase_uid'];
                if (userId != null && userId.toString().isNotEmpty) {
                  print('いいね送信: ユーザープロフィールに遷移 - $userId');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(
                        userId: userId.toString(),
                      ),
                    ),
                  );
                } else {
                  print('いいね送信: ユーザーIDが見つかりません - $like');
                  // 利用可能なフィールドをすべて出力してデバッグ
                  print('利用可能なフィールド: ${like.keys.toList()}');
                }
              },
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
                  if (like['occupation'] != null)
                    Text(like['occupation']),
                ],
              ),
              trailing: const Icon(
                Icons.favorite,
                color: Colors.pink,
                size: 24,
              ),
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
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              onTap: () {
                // 複数のIDフィールドを確認してユーザーIDを取得
                final userId = like['liker_id'] ?? 
                              like['sender_id'] ?? 
                              like['id'] ?? 
                              like['user_id'] ?? 
                              like['firebase_uid'];
                if (userId != null && userId.toString().isNotEmpty) {
                  print('いいね受信: ユーザープロフィールに遷移 - $userId');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(
                        userId: userId.toString(),
                      ),
                    ),
                  );
                } else {
                  print('いいね受信: ユーザーIDが見つかりません - $like');
                  // 利用可能なフィールドをすべて出力してデバッグ
                  print('利用可能なフィールド: ${like.keys.toList()}');
                }
              },
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
                  if (like['occupation'] != null)
                    Text(like['occupation']),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.pink[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, color: Colors.pink, size: 16),
                    SizedBox(width: 4),
                    Text('受信', style: TextStyle(color: Colors.pink, fontSize: 12)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRestaurantsTab() {
    if (_likedRestaurants.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'まだレストランをお気に入りに追加していません',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'レストランを見つけて、お気に入りに追加しましょう！',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLikedRestaurants,
      child: ListView.builder(
        itemCount: _likedRestaurants.length,
        itemBuilder: (context, index) {
          final restaurant = _likedRestaurants[index];
          final restaurantId = restaurant['id']?.toString() ?? '';
          final currentLikeState = _currentLikedRestaurants.contains(restaurantId);
          
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: () {
                // レストラン詳細画面への遷移
                final restaurantId = restaurant['id']?.toString() ?? '';
                print('レストラン詳細画面に遷移 - $restaurantId: ${restaurant['name']}');
                
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
                height: 126, // 13px高くする（113 + 13 = 126）
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左側の画像（カードの高さに完全一致）
                    ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                      child: SizedBox(
                        width: 126, // カードの高さと同じ正方形
                        height: 126, // カードの高さと完全一致
                        child: (() {
                          final imageUrl = restaurant['photo_url'] ?? restaurant['image_url'];
                          if (imageUrl != null && imageUrl.isNotEmpty) {
                            return kIsWeb 
                                ? _buildWebImage(imageUrl, width: 126, height: 126)
                                : Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[200],
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.restaurant,
                                              size: 24,
                                              color: Colors.grey[400],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'No Image',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                          } else {
                            return Container(
                              color: Colors.grey[200],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.restaurant,
                                    size: 24,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'No Image',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        })(),
                      ),
                    ),
                    // 右側の情報
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 店名（改行対応）
                            Text(
                              restaurant['name']?.toString() ?? 'レストラン名未設定',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // 情報とボタンを横並び
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 左側：カテゴリ・都道府県/駅・料金
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                        const SizedBox(height: 2),
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
                                        // 営業時間（source_text）
                                        if (restaurant['operating_hours'] != null && 
                                            restaurant['operating_hours']['source_text'] != null) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            restaurant['operating_hours']['source_text'].toString(),
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: Colors.grey[500],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // 右側：いいねボタンと三点ボタン
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // いいねボタン
                                      GestureDetector(
                                        onTap: () {
                                          _toggleRestaurantLike(restaurantId, currentLikeState);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: currentLikeState ? Colors.pink : Colors.grey[200],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            currentLikeState ? Icons.favorite : Icons.favorite_border,
                                            color: currentLikeState ? Colors.white : Colors.grey[600],
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
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
                    backgroundColor: Colors.orange[600],
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