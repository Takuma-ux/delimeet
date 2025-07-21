import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/web_image_helper.dart';

class FavoriteStoresPage extends StatefulWidget {
  const FavoriteStoresPage({Key? key}) : super(key: key);

  @override
  _FavoriteStoresPageState createState() => _FavoriteStoresPageState();
}

class _FavoriteStoresPageState extends State<FavoriteStoresPage> {
  List<dynamic> _likedRestaurants = [];
  Set<String> _currentLikedRestaurants = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLikedRestaurants();
  }

  Future<void> _loadLikedRestaurants() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('getUserFavoriteRestaurants');
      final result = await callable();
      
      if (result.data['success'] == true) {
        setState(() {
          _likedRestaurants = result.data['restaurants'] ?? [];
          _currentLikedRestaurants = _likedRestaurants
              .map((restaurant) => restaurant['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data['message'] ?? 'お気に入りレストランの取得に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラーが発生しました: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
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
      
      // タイムアウトを短く設定（restaurant_search_page.dartと同様）
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お気に入りのお店'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLikedRestaurants,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pink),
            )
          : _likedRestaurants.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.store, size: 64, color: Colors.grey),
                      SizedBox(height: 20),
                      Text(
                        'お気に入りのお店はありません',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'レストランにいいねすると\nここに表示されます',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _likedRestaurants.length,
                  itemBuilder: (context, index) {
                    final restaurant = _likedRestaurants[index];
                    final restaurantId = restaurant['id'] ?? '';
                    final isLiked = _currentLikedRestaurants.contains(restaurantId);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      child: Container(
                        height: 160, // カード全体の高さを160px
                        child: Row(
                          children: [
                            // レストラン画像（restaurant_search_page.dartと同様のスタイル）
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                              child: Container(
                                width: 160, // カードの高さと同じ正方形
                                height: 160, // カードの高さと完全一致
                                color: Colors.grey[300],
                                child: WebImageHelper.buildRestaurantImage(
                                  restaurant['image_url'],
                                  width: 160,
                                  height: 160,
                                ),
                              ),
                            ),
                            
                            // レストラン情報
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      restaurant['name'] ?? 'レストラン名不明',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      restaurant['category'] ?? 'カテゴリ不明',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatPriceRange(restaurant),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.pink,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (restaurant['address'] != null)
                                      Text(
                                        restaurant['address'],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            
                            // いいねボタン
                            Padding(
                              padding: const EdgeInsets.only(right: 16, top: 16),
                              child: Column(
                                children: [
                                  Container(
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
                                    child: IconButton(
                                      icon: Icon(
                                        isLiked ? Icons.favorite : Icons.favorite_border,
                                        color: isLiked ? Colors.red : Colors.grey,
                                        size: 20,
                                      ),
                                      onPressed: () => _toggleRestaurantLike(restaurantId, isLiked),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
} 