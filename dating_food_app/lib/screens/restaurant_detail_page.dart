import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../models/restaurant_model.dart';
import 'badge_photo_setup_page.dart';
import '../services/web_image_helper.dart';
import '../services/user_image_service.dart';
import 'profile_view_page.dart';
import 'package:firebase_core/firebase_core.dart';

class RestaurantDetailPage extends StatefulWidget {
  final Restaurant restaurant;
  final String? dateRequestId;
  final bool isGroupDate;
  final bool isOrganizer;

  const RestaurantDetailPage({
    super.key,
    required this.restaurant,
    this.dateRequestId,
    this.isGroupDate = false,
    this.isOrganizer = false,
  });

  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _reviews = [];
  Map<String, dynamic>? _reviewStats;
  bool _isLoadingReviews = true;
  bool _isLoadingBadge = true;
  Map<String, dynamic>? _userBadge;
  bool _hasUserReviewed = false;
  List<Map<String, dynamic>> _badgePhotos = [];
  bool _isLoadingBadgePhotos = true;
  List<Map<String, dynamic>> _restaurantUserImages = [];
  bool _isLoadingRestaurantUserImages = true;
  List<String> _likedRestaurants = []; // お気に入りレストランのIDを管理

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReviews();
    _loadUserBadge();
    _checkUserReview();
    _loadRestaurantUserImages();
    _loadLikedRestaurants(); // お気に入りレストランをロード
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    if (!mounted) return;

    setState(() {
      _isLoadingReviews = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getRestaurantReviews');
      final result = await callable.call({
        'restaurantId': widget.restaurant.id,
        'limit': 50,
      });

      if (mounted) {
        setState(() {
          _reviews = List<Map<String, dynamic>>.from(result.data['reviews'] ?? []);
          _reviewStats = result.data['stats'];
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingReviews = false;
        });
      }
    }
  }

  Future<void> _loadUserBadge() async {
    if (!mounted) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getLocalGuideBadge');
      final result = await callable.call({});

      if (mounted) {
        setState(() {
          _userBadge = result.data['badge'];
          _isLoadingBadge = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBadge = false;
        });
      }
    }
  }

  Future<void> _checkUserReview() async {
    if (!mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Cloud Functionsからレビューチェック
      final callable = FirebaseFunctions.instance.httpsCallable('checkUserReview');
      final result = await callable.call({
        'restaurantId': widget.restaurant.id,
      });

      if (mounted) {
        setState(() {
          _hasUserReviewed = result.data['hasReviewed'] ?? false;
        });
      }
    } catch (e) {
      print("レビューチェックエラー: $e");
      // エラー時は既存のローカルチェックを使用
      if (mounted) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final hasReviewed = _reviews.any((review) {
            return review['user_id'] == user.uid || review['user_name'] == user.displayName;
          });
          setState(() {
            _hasUserReviewed = hasReviewed;
          });
        }
      }
    }
  }

  Future<void> _loadBadgePhotos() async {
    if (!mounted) return;

    setState(() {
      _isLoadingBadgePhotos = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getRestaurantBadgePhotos');
      final result = await callable.call({
        'restaurantId': widget.restaurant.id,
      });

      if (mounted) {
        setState(() {
          _badgePhotos = List<Map<String, dynamic>>.from(result.data['photos'] ?? []);
          _isLoadingBadgePhotos = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBadgePhotos = false;
        });
      }
    }
  }

  Future<void> _loadRestaurantUserImages() async {
    setState(() {
      _isLoadingRestaurantUserImages = true;
    });
    try {
      final images = await UserImageService.getUserImages();
      final filtered = images.where((img) => img['restaurant_id'] == widget.restaurant.id).toList();
      setState(() {
        _restaurantUserImages = filtered;
        _isLoadingRestaurantUserImages = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingRestaurantUserImages = false;
      });
    }
  }

  Future<void> _loadLikedRestaurants() async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'us-central1',
        app: Firebase.app(),
      );
      final callable = functions.httpsCallable('getLikedRestaurants');
      final result = await callable().timeout(const Duration(seconds: 3));
      
      if (mounted) {
        setState(() {
          _likedRestaurants = List<String>.from(result.data ?? []);
        });
      }
    } catch (e) {
      // エラー時は空の状態を維持
    }
  }

  Future<void> _toggleRestaurantLike(String restaurantId, bool isLiked) async {
    if (!mounted) return;

    setState(() {
      if (isLiked) {
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
        isLiked ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      
      await callable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 5));
      
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isLiked) {
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

  void _showReviewDialog() async {
    // レビューチェックを最新の状態に更新
    await _checkUserReview();
    
    // 既にレビューを投稿している場合はモーダルを開かない
    if (_hasUserReviewed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('既にこのレストランのレビューを投稿済みです'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => ReviewDialog(
        restaurant: widget.restaurant,
        dateRequestId: widget.dateRequestId,
        isGroupDate: widget.isGroupDate,
        isOrganizer: widget.isOrganizer,
        onReviewSubmitted: () {
          _loadReviews();
          _loadUserBadge();
          _checkUserReview();
        },
      ),
    );
  }

  void _likeReview(String reviewId, bool isLiked) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        isLiked ? 'unlikeReview' : 'likeReview'
      );
      await callable.call({'reviewId': reviewId});
      
      // レビュー一覧を再読み込み
      _loadReviews();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('いいね操作に失敗しました: $e')),
      );
    }
  }

  Widget _buildBadgeIcon(String badgeLevel) {
    IconData iconData;
    Color color;
    String label;

    switch (badgeLevel) {
      case 'platinum':
        iconData = Icons.diamond;
        color = Colors.grey[400]!;
        label = 'プラチナ';
        break;
      case 'gold':
        iconData = Icons.star;
        color = Colors.amber;
        label = 'ゴールド';
        break;
      case 'silver':
        iconData = Icons.star_border;
        color = Colors.grey[600]!;
        label = 'シルバー';
        break;
      default:
        iconData = Icons.circle;
        color = Colors.brown;
        label = 'ブロンズ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingStars(double rating) {
    return Row(
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, color: Colors.amber, size: 16);
        } else if (index == rating.floor() && rating % 1 > 0) {
          return Icon(Icons.star_half, color: Colors.amber, size: 16);
        } else {
          return const Icon(Icons.star_border, color: Colors.amber, size: 16);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurant.name),
        backgroundColor: const Color(0xFFFFEFD5),
        foregroundColor: Colors.white,
        actions: [
          // いいねボタン
          IconButton(
            onPressed: () {
              final restaurantId = widget.restaurant.id;
              final isLiked = _likedRestaurants.contains(restaurantId);
              _toggleRestaurantLike(restaurantId, isLiked);
            },
            icon: Icon(
              _likedRestaurants.contains(widget.restaurant.id)
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: Colors.white,
            ),
            tooltip: 'お気に入り',
          ),
          if (!_hasUserReviewed)
            IconButton(
              onPressed: _showReviewDialog,
              icon: const Icon(Icons.rate_review),
              tooltip: 'レビューを書く',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // レストラン基本情報
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // レストラン画像（小さく左寄せ）
                  if (widget.restaurant.imageUrl != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左寄せの小さな画像
                        Container(
                          width: 80, // 200 → 80に縮小（1/2.5倍）
                          height: 60, // 200 → 60に縮小（3:2比率を維持）
                          margin: const EdgeInsets.only(bottom: 16, right: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: WebImageHelper.buildRestaurantImage(
                              widget.restaurant.imageUrl!,
                              width: 80,
                              height: 60,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        // 右側の空きスペース（必要に応じてレストラン情報を追加可能）
                        Expanded(
                          child: Container(
                            height: 60,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.restaurant.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  // プロフィール画像のうちこのレストランに紐付いた画像一覧
                  _buildRestaurantUserImagesGrid(),
                  
                  const SizedBox(height: 8),
                  
                  // カテゴリ
                  if (widget.restaurant.category != null) ...[
                    Row(
                      children: [
                        Icon(Icons.category, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          widget.restaurant.category!,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  
                  // 所在地
                  if (widget.restaurant.prefecture != null) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          widget.restaurant.prefecture!,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  
                  // 最寄駅
                  if (widget.restaurant.nearestStation != null) ...[
                    Row(
                      children: [
                        Icon(Icons.train, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.restaurant.nearestStation!}駅',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  
                  // 価格帯
                  if (widget.restaurant.priceRange != null) ...[
                    Row(
                      children: [
                        Icon(Icons.attach_money, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          widget.restaurant.priceRange!,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  
                  // 平均評価
                  if (_reviewStats != null) ...[
                    Row(
                      children: [
                        _buildRatingStars(_reviewStats!['averageRating'] ?? 0.0),
                        const SizedBox(width: 8),
                        Text(
                          '${_reviewStats!['averageRating']?.toStringAsFixed(1) ?? '0.0'}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${_reviewStats!['totalReviews'] ?? 0}件のレビュー)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // アクションボタン
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (widget.restaurant.hotpepperUrl != null) {
                              launchUrl(Uri.parse(widget.restaurant.hotpepperUrl!));
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('詳細を見る'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_hasUserReviewed)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showReviewDialog,
                            icon: const Icon(Icons.rate_review),
                            label: const Text('レビューを書く'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFEFD5),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            // タブバー
            Container(
              color: Colors.grey[100],
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFFF2C9AC),
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: const Color(0xFFF2C9AC),
                tabs: const [
                  Tab(text: 'レビュー'),
                  Tab(text: '地元案内人'),
                ],
              ),
            ),
            
            // タブコンテンツ
            Container(
              height: 600, // 固定高さを設定
              child: TabBarView(
                controller: _tabController,
                children: [
                  // レビュータブ
                  _buildReviewsTab(),
                  
                  // 地元案内人タブ
                  _buildLocalGuideTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsTab() {
    if (_isLoadingReviews) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reviews.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'まだレビューがありません',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '最初のレビューを投稿してみませんか？',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // レビュー統計
          if (_reviewStats != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'レビュー統計',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '平均評価: ${_reviewStats!['averageRating']?.toStringAsFixed(1) ?? '0.0'}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '総レビュー数: ${_reviewStats!['totalReviews'] ?? 0}件',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // レビューリスト
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reviews.length,
            itemBuilder: (context, index) {
              final review = _reviews[index];
              final rating = review['rating'] as int;
              final comment = review['comment'] as String?;
              final userName = review['user_name'] as String? ?? 'ユーザー';
              final userImageUrl = review['user_image_url'] as String?;
              final helpfulCount = review['helpful_count'] as int? ?? 0;
              final userId = review['user_id'] as String?;
              final isGroupDate = review['is_group_date'] as bool? ?? false;
              final isOrganizer = review['is_organizer'] as bool? ?? false;
              final badgeLevel = review['badge_level'] as String?;
              final isLiked = review['is_liked'] as bool? ?? false;
              
              // 現在のユーザーIDを取得
              final currentUser = FirebaseAuth.instance.currentUser;
              final currentUserId = currentUser?.uid;
              final isOwnReview = currentUserId != null && userId == currentUserId;
              
              // visit_dateのガード
              String? visitDateStr;
              if (review['visit_date'] is String && review['visit_date'].toString().isNotEmpty) {
                visitDateStr = review['visit_date'];
              } else {
                visitDateStr = null;
              }
              
              // created_atのガード
              String? createdAtStr;
              if (review['created_at'] is String && review['created_at'].toString().isNotEmpty) {
                createdAtStr = review['created_at'];
              } else {
                createdAtStr = null;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ユーザー情報
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (userId != null && userId.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProfileViewPage(userId: userId),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ユーザー情報が取得できませんでした'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundImage: userImageUrl != null
                                    ? NetworkImage(userImageUrl)
                                    : null,
                                child: userImageUrl == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        if (userId != null && userId.isNotEmpty) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ProfileViewPage(userId: userId),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('ユーザー情報が取得できませんでした'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue),
                                        ),
                                        child: Text(
                                          userName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (badgeLevel != null)
                                      _buildBadgeIcon(badgeLevel),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _buildRatingStars(rating.toDouble()),
                                    const SizedBox(width: 8),
                                    if (isGroupDate)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue),
                                        ),
                                        child: Text(
                                          isOrganizer ? '主催者' : '参加者',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue[700],
                                            fontWeight: FontWeight.bold,
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
                      const SizedBox(height: 12),
                      // レビューコメント
                      if (comment != null && comment.isNotEmpty) ...[
                        Text(
                          comment,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // 訪問日
                      if (visitDateStr != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 14, color: Colors.orange[700]),
                              const SizedBox(width: 4),
                              Text(
                                '訪問日: ${DateFormat('yyyy年MM月dd日').format(DateTime.parse(visitDateStr))}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // 投稿日時といいねボタン
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            createdAtStr != null
                                ? DateFormat('yyyy年MM月dd日').format(DateTime.parse(createdAtStr))
                                : '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: isOwnReview ? null : () => _likeReview(review['id'], isLiked),
                                icon: Icon(
                                  isOwnReview 
                                    ? Icons.thumb_up 
                                    : (isLiked ? Icons.thumb_up : Icons.thumb_up_outlined),
                                  color: isOwnReview ? Colors.grey : (isLiked ? Colors.blue : null),
                                ),
                                iconSize: 20,
                                tooltip: isOwnReview 
                                  ? '自分のレビューにはいいねできません' 
                                  : (isLiked ? 'いいね済み' : 'いいね'),
                              ),
                              Text(
                                helpfulCount.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isOwnReview ? Colors.grey : null,
                                ),
                              ),
                            ],
                          ),
                        ],
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

  Widget _buildLocalGuideTab() {
    if (_isLoadingBadge) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // バッジ説明
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '地元案内人バッジについて',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '地元案内人バッジは、レストラン情報の共有に貢献したユーザーに贈られるバッジです。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  
                  // バッジレベル説明
                  _buildBadgeLevelInfo('bronze', 'ブロンズ', '0-49点', '初心者'),
                  _buildBadgeLevelInfo('silver', 'シルバー', '50-99点', '中級者'),
                  _buildBadgeLevelInfo('gold', 'ゴールド', '100-199点', '上級者'),
                  _buildBadgeLevelInfo('platinum', 'プラチナ', '200点以上', 'エキスパート'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 得点獲得方法
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '得点獲得方法',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildScoreMethod('レビュー投稿', '個人デート: 5点 / 団体デート: 主催者10点・メンバー5点'),
                  _buildScoreMethod('レビューの参考になった', '3点/件'),
                  _buildScoreMethod('お気に入りレストラン設定', '5点/店舗'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
                          // バッジ写真セクション
                if (_badgePhotos.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '地元案内人の写真',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'このレストランで撮影された地元案内人の写真です',
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          _buildBadgePhotosGrid(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ユーザーのバッジ情報
                if (_userBadge != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'あなたのバッジ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildBadgeIcon(_userBadge!['badge_level']),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '総得点: ${_userBadge!['total_score']}点',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('レビュー投稿: ${_userBadge!['review_points']}点'),
                                    Text('参考になった: ${_userBadge!['helpful_points']}点'),
                                    Text('お気に入り設定: ${_userBadge!['favorite_restaurant_points']}点'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
        ],
      ),
    );
  }

  Widget _buildBadgeLevelInfo(String level, String name, String range, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _buildBadgeIcon(level),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$range ($description)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreMethod(String method, String points) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  points,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgePhotosGrid() {
    if (_isLoadingBadgePhotos) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_badgePhotos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'まだバッジ写真がありません',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '最初のバッジ写真を設定してみませんか？',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _badgePhotos.length,
      itemBuilder: (context, index) {
        final photo = _badgePhotos[index];
        final photoUrl = photo['photo_url'] as String?;
        final userName = photo['user_name'] as String? ?? 'ユーザー';
        final badgeLevel = photo['badge_level'] as String?;

        return GestureDetector(
          onTap: () => _showPhotoDetail(photo),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                children: [
                  // 写真表示
                  Positioned.fill(
                    child: photoUrl != null
                        ? WebImageHelper.buildImage(
                            photoUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(7),
                          )
                        : Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.photo, color: Colors.grey),
                          ),
                  ),
                  
                  // ユーザー情報オーバーレイ
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (badgeLevel != null)
                            _buildBadgeIcon(badgeLevel),
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
    );
  }

  Widget _buildRestaurantUserImagesGrid() {
    if (_isLoadingRestaurantUserImages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_restaurantUserImages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'このレストランに紐付いた写真はありません',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'プロフィール編集画面から写真を追加できます',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _restaurantUserImages.length,
      itemBuilder: (context, index) {
        final image = _restaurantUserImages[index];
        return GestureDetector(
          onTap: () => _showPhotoDetail(image),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: WebImageHelper.buildImage(
                image['image_url'],
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPhotoDetail(Map<String, dynamic> image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 写真
            if (image['image_url'] != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: WebImageHelper.buildImage(
                  image['image_url'],
                  width: double.infinity,
                  height: 300,
                  fit: BoxFit.cover,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
              ),
            // キャプション
            if (image['caption'] != null && image['caption'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  image['caption'],
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReviewDialog extends StatefulWidget {
  final Restaurant restaurant;
  final String? dateRequestId;
  final bool isGroupDate;
  final bool isOrganizer;
  final VoidCallback onReviewSubmitted;

  const ReviewDialog({
    super.key,
    required this.restaurant,
    this.dateRequestId,
    this.isGroupDate = false,
    this.isOrganizer = false,
    required this.onReviewSubmitted,
  });

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final TextEditingController _commentController = TextEditingController();
  int _rating = 5;
  DateTime? _visitDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    if (!mounted) return;
    
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _visitDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('ja', 'JP'), // 日本語化を復活
      );
      
      if (mounted && picked != null && picked != _visitDate) {
        setState(() {
          _visitDate = picked;
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        // エラーが発生した場合は現在の日付を設定
        setState(() {
          _visitDate = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('日付選択でエラーが発生しました: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _submitReview() async {
    if (_isSubmitting) return;

    // バリデーション: 訪問日が必須
    if (_visitDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('訪問日を選択してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('submitRestaurantReview');
      await callable.call({
        'restaurantId': widget.restaurant.id,
        'rating': _rating,
        'comment': _commentController.text.trim(),
        'visitDate': _visitDate!.toIso8601String().split('T')[0],
        'dateRequestId': widget.dateRequestId,
        'isGroupDate': widget.isGroupDate,
        'isOrganizer': widget.isOrganizer,
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onReviewSubmitted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レビューを投稿しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('レビューの投稿に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.restaurant.name}のレビュー'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 評価
            const Text(
              '評価',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  onPressed: () {
                    setState(() {
                      _rating = index + 1;
                    });
                  },
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 16),
            
            // 訪問日
            Row(
              children: [
                const Text(
                  '訪問日',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '必須',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                _selectDate();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _visitDate == null ? Colors.red : Colors.grey,
                    width: _visitDate == null ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: _visitDate == null ? Colors.red : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _visitDate != null && _visitDate is DateTime
                          ? DateFormat('yyyy年MM月dd日').format(_visitDate!)
                          : '日付を選択してください',
                      style: TextStyle(
                        color: _visitDate == null ? Colors.red : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // コメント
            const Text(
              'コメント（任意）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'レストランの感想を書いてください',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: (_isSubmitting || _visitDate == null) ? null : _submitReview,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('投稿'),
        ),
      ],
    );
  }
} 