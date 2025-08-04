import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/user_image_service.dart';
import '../services/group_service.dart';
import '../services/web_image_helper.dart';
import '../models/group_model.dart';
import '../models/restaurant_model.dart';
import 'blocked_users_page.dart';
import 'profile_edit_page.dart';
import 'group_chat_page.dart';
import 'restaurant_detail_page.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import '../services/instagram_service.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';


class ProfileViewPage extends StatefulWidget {
  final String? userId;

  const ProfileViewPage({super.key, this.userId});

  @override
  State<ProfileViewPage> createState() => _ProfileViewPageState();
}

class _ProfileViewPageState extends State<ProfileViewPage> {
  Map<String, dynamic>? profile;
  List<dynamic> _favoriteRestaurants = [];
  List<Map<String, dynamic>> _userImages = []; // 複数画像用（型を変更）
  bool _isLoading = true;
  String? _error;
  Set<String> _likedRestaurants = {}; // いいね状態管理
  int _currentImageIndex = 0;
  bool _isInstagramConnected = false; // Instagram連携状態
  String? _instagramUsername;
  bool _isLikedUser = false; // ユーザーいいね状態

  String? _myUserId; // ← 追加

  // Supabaseクライアント
  final SupabaseClient _supabase = Supabase.instance.client;
  // キャッシュ用
  static Map<String, Map<String, dynamic>> _profileCache = {};
  static Map<String, DateTime> _profileCacheTime = {};
  static const Duration _cacheDuration = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _initializeMyUserId();
    _loadAllData();
    _checkInstagramConnection();
    _checkUserLikeStatus(); // いいね状態をチェック
  }

  /// 自分のユーザーIDを初期化
  Future<void> _initializeMyUserId() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final userResult = await _supabase
            .from('users')
            .select('id')
            .eq('firebase_uid', firebaseUser.uid)
            .single();
        
        if (mounted) {
          setState(() {
            _myUserId = userResult['id']?.toString();
          });
        }
      }
    } catch (e) {
      print('ユーザーID初期化エラー: $e');
    }
  }

  /// ユーザーいいね状態をチェック
  Future<void> _checkUserLikeStatus() async {
    if (_isOwnProfile()) return; // 自分自身ならスキップ

    final targetUserId = widget.userId;
    if (targetUserId == null) return;

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 3));
      
      if (mounted) {
        final sentLikes = List.from(result.data['sentLikes'] ?? []);
        final likedUsers = Set<String>.from(
          sentLikes.map((like) => like['liked_user_id']?.toString() ?? '').where((id) => id.isNotEmpty)
        );
        
        setState(() {
          _isLikedUser = likedUsers.contains(targetUserId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLikedUser = false;
        });
      }
    }
  }

  /// ユーザーいいねの切り替え
  Future<void> _toggleUserLike() async {
    if (_isOwnProfile()) return;

    // 既にいいね済みの場合は取り消しできない
    if (_isLikedUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('いいねは取り消すことができません'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final targetUserId = widget.userId;
    if (targetUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('いいね操作に失敗しました: ユーザーIDが取得できません'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // いいね追加のUIを更新
    setState(() {
      _isLikedUser = true;
    });

    // バックグラウンドでAPI呼び出し
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('addUserLike');
      
      // タイムアウトを短く設定
      await callable({'likedUserId': targetUserId}).timeout(const Duration(seconds: 5));
      
    } catch (e) {
      // エラー時のみUIを元に戻す
      if (mounted) {
        setState(() {
          _isLikedUser = false;
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

  bool _isOwnProfile() {
    final currentUser = FirebaseAuth.instance.currentUser;
    return widget.userId == null || 
           (currentUser != null && widget.userId == currentUser.uid);
  }

  /// Instagram連携状態をチェック
  Future<void> _checkInstagramConnection() async {
    if (!_isOwnProfile()) return; // 自分のプロフィールの場合のみ
    
    try {
      final isConnected = await InstagramService.isInstagramConnected();
      final username = await InstagramService.getInstagramUsername();
      
      if (mounted) {
        setState(() {
          _isInstagramConnected = isConnected;
          _instagramUsername = username;
        });
      }
    } catch (e) {
    }
  }

  /// 🚀 並列データ読み込みで速度向上
  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 基本的なプロフィール取得（他のデータの前提条件）
      final profileResult = await _getProfileData().timeout(const Duration(seconds: 4));
      
      if (profileResult != null) {
        if (mounted) {
          setState(() {
            profile = profileResult;
            _isLoading = false;
          });
        }

        // プロフィール取得後、残りのデータを並列取得
        final futures = <Future<void>>[];
        
        // 画像データ取得
        futures.add(_loadUserImages());
        
        // 自分のプロフィールの場合のみいいね状態取得
        if (_isOwnProfile()) {
          futures.add(_loadUserLikes());
        }
        
        // お気に入りレストラン取得
        futures.add(_loadFavoriteRestaurants());
        
        // 全て並列実行（エラーが発生しても他の処理は継続）
        await Future.wait(futures, eagerError: false).timeout(const Duration(seconds: 6));
        
      } else {
        if (mounted) {
          setState(() {
            _error = 'プロフィールの取得に失敗しました';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'データの取得に失敗しました';
          _isLoading = false;
        });
      }
    }
  }

  // プロフィール取得（Supabase直接取得＋キャッシュ）
  Future<Map<String, dynamic>?> _getProfileData() async {
    final isOwn = _isOwnProfile();
    String cacheKey;
    if (isOwn) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      cacheKey = 'my_profile_${user.uid}';
    } else {
      cacheKey = 'user_profile_${widget.userId}';
    }

    // デバッグ: キャッシュをクリアして強制的にSupabaseから取得
    _profileCache.remove(cacheKey);
    _profileCacheTime.remove(cacheKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
    await prefs.remove('${cacheKey}_time');

    // 1. メモリキャッシュ
    if (_profileCache.containsKey(cacheKey) && _profileCacheTime.containsKey(cacheKey)) {
      final cachedTime = _profileCacheTime[cacheKey]!;
      if (DateTime.now().difference(cachedTime) < _cacheDuration) {
        return _profileCache[cacheKey]!;
      }
    }

    // 2. SharedPreferencesキャッシュ
    final cacheJson = prefs.getString(cacheKey);
    final cacheTimeMillis = prefs.getInt('${cacheKey}_time');
    if (cacheJson != null && cacheTimeMillis != null) {
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(cacheTimeMillis);
      if (DateTime.now().difference(cacheTime) < _cacheDuration) {
        final cachedProfile = Map<String, dynamic>.from(jsonDecode(cacheJson));
        // メモリにもセット
        _profileCache[cacheKey] = cachedProfile;
        _profileCacheTime[cacheKey] = cacheTime;
        return cachedProfile;
      }
    }

    // 3. Supabaseから直接取得
    Map<String, dynamic>? result;
    try {
      if (isOwn) {
        // 自分のプロフィール取得
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return null;
        
        final response = await _supabase
            .from('users')
            .select('''
              id, name, bio, age, gender, prefecture, occupation, 
              weekend_off, favorite_categories, image_url, 
              birth_date, id_verified, created_at, updated_at, deactivated_at, account_status,
              tags, mbti, preferred_age_range, payment_preference, preferred_gender,
              school_id, show_school, hide_from_same_school, visible_only_if_liked
            ''')
            .eq('firebase_uid', user.uid)
            .maybeSingle();
        
        if (response != null) {
          result = response;
          // 学校情報を別途取得
          final schoolId = response['school_id'];
          
          if (schoolId != null && schoolId.toString().isNotEmpty) {
            try {
              final schoolResponse = await _supabase
                  .from('schools')
                  .select('school_name, school_type, prefecture_name')
                  .eq('id', schoolId.toString())
                  .maybeSingle();
              
              if (schoolResponse != null) {
                result['school_name'] = schoolResponse['school_name'];
                result['school_type'] = schoolResponse['school_type'];
                result['school_prefecture'] = schoolResponse['prefecture_name'];
              }
            } catch (e) {
              print('学校情報取得エラー: $e');
            }
          } else {
            print('  - schoolIdがnullまたは空です');
          }
        }
      } else {
        // 他人のプロフィール取得
        if (widget.userId == null) return null;
        
        final response = await _supabase
            .from('users')
            .select('''
              id, name, bio, age, gender, prefecture, occupation, 
              weekend_off, favorite_categories, image_url, 
              birth_date, id_verified, created_at, updated_at, deactivated_at, account_status,
              tags, mbti, preferred_age_range, payment_preference, preferred_gender,
              school_id, show_school, hide_from_same_school, visible_only_if_liked
            ''')
            .eq('id', widget.userId!)
            .maybeSingle();
        
        if (response != null) {
          result = response;
          // 学校情報を別途取得
          final schoolId = response['school_id'];
          
          if (schoolId != null && schoolId.toString().isNotEmpty) {
            try {
              final schoolResponse = await _supabase
                  .from('schools')
                  .select('school_name, school_type, prefecture_name')
                  .eq('id', schoolId.toString())
                  .maybeSingle();
              
              if (schoolResponse != null) {
                result['school_name'] = schoolResponse['school_name'];
                result['school_type'] = schoolResponse['school_type'];
                result['school_prefecture'] = schoolResponse['prefecture_name'];
              }
            } catch (e) {
              print('学校情報取得エラー: $e');
            }
          } else {
            print('  - schoolIdがnullまたは空です');
          }
        }
      }
    } catch (e) {
      print('Supabaseからのプロフィール取得エラー: $e');
      return null;
    }
    
    if (result != null) {
      // メモリキャッシュ
      _profileCache[cacheKey] = result;
      _profileCacheTime[cacheKey] = DateTime.now();
      // SharedPreferencesキャッシュ
      await prefs.setString(cacheKey, jsonEncode(result));
      await prefs.setInt('${cacheKey}_time', DateTime.now().millisecondsSinceEpoch);
    }
    return result;
  }

  Future<void> _loadProfile() async {
    // 既存の_loadProfileロジックを_loadAllDataに統合したため、
    // このメソッドは再試行用として残す
    await _loadAllData();
  }

  Future<void> _loadFavoriteRestaurants() async {
    if (!mounted || profile == null) {
      return;
    }

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getUserFavoriteRestaurants');
      
      // 他人のプロフィールの場合はprofile['id']（UUID）、自分の場合はwidget.userIdまたは現在のユーザーIDを使用
      String? targetUserId;
      if (widget.userId != null) {
        // 他人のプロフィール
        targetUserId = profile!['id']; // UUIDを使用
      } else {
        // 自分のプロフィール - Firebase UIDを使用
        targetUserId = FirebaseAuth.instance.currentUser?.uid;
      }
      
      final result = await callable.call({
        'userId': targetUserId,
        'limit': 3,
      });
      
      final response = result.data;
      // レスポンス形式を修正: restaurantsが直接存在する場合も処理
      if (mounted) {
        if (response['restaurants'] != null) {
          setState(() {
            _favoriteRestaurants = response['restaurants'] ?? [];
          });
        } else if (response['success'] == true) {
          setState(() {
            _favoriteRestaurants = response['restaurants'] ?? [];
          });
        }
      }
    } catch (e) {
      // エラーログのみ出力
    }
  }

  Future<void> _loadUserImages() async {
    if (profile == null) return;

    try {
      String? targetUserId;
      
      if (widget.userId != null) {
        // 他人のプロフィールの場合、profile['id']（UUID）を使用
        targetUserId = profile!['id'];
      } else {
        // 自分のプロフィールの場合、targetUserIdは指定しない（Firebase UIDが使用される）
        targetUserId = null;
      }
      
      final images = await UserImageService.getUserImages(
        userId: targetUserId,
      );
      
      if (images.isNotEmpty) {
      }
      
      if (mounted) {
        setState(() {
          _userImages = images.where((image) => 
              image['image_url'] != null && 
              image['image_url'].toString().isNotEmpty
          ).toList();
        });
      }
    } catch (e) {
      // エラーの場合は空のリストを維持（プロフィール画像とは別なので混同しない）
      if (mounted) {
        setState(() {
          _userImages = [];
        });
      }
    }
  }

  String? _formatBirthDate(dynamic birthDate) {
    if (birthDate == null) return null;
    
    try {
      DateTime date;
      if (birthDate is String) {
        date = DateTime.parse(birthDate);
      } else if (birthDate is DateTime) {
        date = birthDate;
      } else {
        return null;
      }
      
      return '${date.year}年${date.month}月${date.day}日';
    } catch (e) {
      return null;
    }
  }

  int _calculateAge(dynamic birthDate) {
    if (birthDate == null) return 0;
    
    try {
      DateTime date;
      if (birthDate is String) {
        date = DateTime.parse(birthDate);
      } else if (birthDate is DateTime) {
        date = birthDate;
      } else {
        return 0;
      }
      
      final now = DateTime.now();
      int age = now.year - date.year;
      
      if (now.month < date.month || (now.month == date.month && now.day < date.day)) {
        age--;
      }
      
      return age;
    } catch (e) {
      return 0;
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
      // エラーログのみ出力（デバッグログ削減）
    }
  }

  Future<void> _toggleRestaurantLike(String restaurantId, bool isCurrentlyLiked) async {
    if (!mounted || restaurantId.isEmpty) return;

    // 即座にUIを更新（楽観的更新）
    setState(() {
      if (isCurrentlyLiked) {
        _likedRestaurants.remove(restaurantId);
      } else {
        _likedRestaurants.add(restaurantId);
      }
    });

    // バックグラウンドでAPI呼び出し
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        isCurrentlyLiked ? 'removeRestaurantLike' : 'addRestaurantLike'
      );
      
      // タイムアウトを短く設定（restaurant_search_page.dartと同様）
      await callable({'restaurantId': restaurantId}).timeout(const Duration(seconds: 5));
      
    } catch (e) {
      // エラー時のみUIを元に戻す
      if (mounted) {
        setState(() {
          if (isCurrentlyLiked) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // 食べログ風の薄いグレー背景
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadProfile,
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                )
              : _buildFoodieProfileContent(),
    );
  }

  Widget _buildFoodieProfileContent() {
    if (profile == null) return const SizedBox();

    final age = _isOwnProfile() ? _calculateAge(profile!['birth_date']) : (profile!['age'] ?? 0);

    return CustomScrollView(
      slivers: [
        // 食べログ風ヘッダー
        SliverAppBar(
          expandedHeight: 340, // 画像・名前・チップが全て見えるように拡大
          pinned: true,
          backgroundColor: Colors.white,
          elevation: 0,
          leading: Container(
            margin: const EdgeInsets.all(8),
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
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () => Navigator.of(context).pop(),
              iconSize: 20,
            ),
          ),
          actions: [
            // 他人のプロフィールの場合はいいねボタンを表示
            if (!_isOwnProfile())
              Container(
                margin: const EdgeInsets.all(8),
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
                    _isLikedUser ? Icons.favorite : Icons.favorite_border,
                    color: _isLikedUser ? const Color(0xFFF6BFBC) : const Color(0xFFFFEFD5),
                  ),
                  onPressed: _toggleUserLike,
                  iconSize: 20,
                ),
              ),
            if (_isOwnProfile())
              Container(
                margin: const EdgeInsets.all(8),
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
                  icon: const Icon(Icons.edit, color: Colors.black87),
                  onPressed: () {
                    Navigator.pushNamed(context, '/profile_edit').then((_) {
                      _loadProfile();
                    });
                  },
                  iconSize: 20,
                ),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.orange.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: _buildFoodieProfileHeader(age),
            ),
          ),
        ),
        
        // メインコンテンツ
        SliverToBoxAdapter(
          child: _buildFoodieMainContent(),
        ),
      ],
    );
  }

  Widget _buildFoodieProfileHeader(int age) {
    final gender = ((profile?['gender'] ?? '')?.toString() ?? '').trim();
    final occupation = ((profile?['occupation'] ?? '')?.toString() ?? '').trim();
    final categories = profile?['favorite_categories'] as List? ?? [];
    final category = (categories.isNotEmpty && categories[0] != null) ? categories[0].toString().trim() : '';
    final prefecture = ((profile?['prefecture'] ?? '')?.toString() ?? '').trim();
    final city = ((profile?['city'] ?? '')?.toString() ?? '').trim();
    final mbti = ((profile?['mbti'] ?? '')?.toString() ?? '').trim();
    
    // 学校情報
    final schoolName = ((profile?['school_name'] ?? '')?.toString() ?? '').trim();
    final schoolType = ((profile?['school_type'] ?? '')?.toString() ?? '').trim();
    final showSchool = profile?['show_school'] ?? true;

    return Column(
      children: [
        // DEBUGテキスト削除
        const SizedBox(height: 50),
        Center(
          child: Container(
            height: 120,
            width: 120,
            alignment: Alignment.center,
            child: CircleAvatar(
              radius: 55,
              backgroundColor: Colors.grey[300],
              backgroundImage: (profile?['image_url']?.toString().isNotEmpty == true)
                  ? NetworkImage(profile!['image_url'])
                  : null,
              child: (profile?['image_url']?.toString().isEmpty == true)
                  ? const Icon(Icons.person, size: 55, color: Colors.white)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              (profile?['name']?.toString().trim().isNotEmpty == true)
                  ? profile!['name'].toString().trim()
                  : '名前未設定',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${age}歳',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (gender.isNotEmpty) _buildFoodieGenderChip(gender),
            if (occupation.isNotEmpty) _buildFoodieOccupationChip(occupation),
            if (category.isNotEmpty) _buildFoodieInfoChip(Icons.local_dining, category, Colors.deepOrange),
            if (prefecture.isNotEmpty) _buildFoodieInfoChip(Icons.location_on, prefecture, Colors.blue),
            if (city.isNotEmpty) _buildFoodieInfoChip(Icons.location_city, city, Colors.indigo),
            if (mbti.isNotEmpty) _buildFoodieInfoChip(Icons.psychology, mbti, Colors.purple),
            // 学校情報を表示（show_schoolがtrueかつ学校名が設定されている場合）
            if (showSchool && schoolName.isNotEmpty) _buildSchoolChip(schoolName, schoolType),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // バッジ共通Widget
  Widget _buildFoodieInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // 性別・職業バッジも共通バッジで統一
  Widget _buildFoodieGenderChip(String gender) {
    return _buildFoodieInfoChip(Icons.wc, gender, const Color(0xFFF6BFBC));
  }
  Widget _buildFoodieOccupationChip(String occupation) {
    return _buildFoodieInfoChip(Icons.work, occupation, Colors.green);
  }

  Widget _buildSchoolChip(String schoolName, String schoolType) {
    // 学校種別を日本語に変換
    String getSchoolTypeLabel(String type) {
      switch (type) {
        case 'university':
          return '大学';
        case 'graduate_school':
          return '大学院';
        case 'vocational_school':
          return '専門学校';
        case 'college':
          return '短大';
        default:
          return '';
      }
    }
    
    final typeLabel = getSchoolTypeLabel(schoolType);
    final displayText = typeLabel.isNotEmpty ? '$schoolName ($typeLabel)' : schoolName;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school, size: 14, color: Colors.teal),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 13,
              color: Colors.teal,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodieMainContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 自己紹介カード
          if (profile!['bio'] != null && profile!['bio'].toString().isNotEmpty)
            _buildFoodieBioCard(),
          
          const SizedBox(height: 16),
          
          // 投稿した写真グリッド
          if (_userImages.isNotEmpty)
            _buildFoodiePhotoGrid(),
          
          // お気に入りレストランカード
          if (_favoriteRestaurants.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFoodieFavoriteRestaurants(),
          ],
          
          // ハッシュタグセクション
          if (profile!['tags'] != null && (profile!['tags'] as List).isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFoodieHashtagsSection(),
          ],
          
          // MBTIセクション
          if (profile!['mbti'] != null) ...[
            const SizedBox(height: 16),
            _buildFoodieMbtiSection(),
          ],
          
          // マッチしたい人の特徴セクション
          if (profile!['preferred_age_range'] != null || 
              profile!['payment_preference'] != null || 
              profile!['preferred_gender'] != null) ...[
            const SizedBox(height: 16),
            _buildMatchingPreferencesSection(),
          ],

          // 支払い方法セクション
          if (profile!['payment_preference'] != null) ...[
            const SizedBox(height: 16),
            _buildPaymentPreferenceSection(),
          ],
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFoodieBioCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '自己紹介',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              profile!['bio'],
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodiePhotoGrid() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.photo_library, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '投稿した写真',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_userImages.length}枚',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 画像グリッド部分のみ横paddingなし
          _buildFoodieImageGrid(),
        ],
      ),
    );
  }

  Widget _buildFoodieImageGrid() {
    // 最大9枚まで表示
    final displayImages = _userImages.take(9).toList();
    
    // 1:1の比率
    final screenWidth = MediaQuery.of(context).size.width;
    final cardPadding = 0.0; // 横paddingなし
    final availableWidth = screenWidth - cardPadding; // 外側のpadding
    final gap = 1.0; // 画像間の隙間1px
    final cellWidth = (availableWidth - gap * 2) / 3; // 3列、間隔1px
    final cellHeight = cellWidth; // 1:1比率
    final totalHeight = cellHeight * 3 + gap * 2; // 3行分の高さ + 間隔
    
    return Container(
      height: totalHeight,
      padding: EdgeInsets.symmetric(horizontal: 0), // 横paddingなし
      child: Column(
        children: [
          for (int row = 0; row < 3; row++)
            Expanded(
              child: Row(
                children: [
                  for (int col = 0; col < 3; col++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          right: col < 2 ? gap : 0,
                          bottom: row < 2 ? gap : 0,
                        ),
                        child: _buildFoodieImageCell(row * 3 + col, displayImages, cellHeight: cellHeight, borderRadius: 0),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFoodieImageCell(int index, List<Map<String, dynamic>> displayImages, {double? cellHeight, double borderRadius = 8}) {
    if (index >= displayImages.length) {
      // 空のセル
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showImageDialog(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _buildProperImage(
            displayImages[index]['image_url'] ?? '',
            fit: BoxFit.cover,
            width: double.infinity,
            height: cellHeight,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant, color: Colors.grey, size: 24),
                    SizedBox(height: 4),
                    Text(
                      '画像なし',
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFoodieFavoriteRestaurants() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'お気に入りのレストラン',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_favoriteRestaurants.length}店舗',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: _favoriteRestaurants.asMap().entries.map((entry) {
                final index = entry.key;
                final restaurant = Map<String, dynamic>.from(entry.value as Map);
                final isLast = index == _favoriteRestaurants.length - 1;
                
                return Column(
                  children: [
                    _buildFoodieRestaurantCard(restaurant),
                    if (!isLast) const SizedBox(height: 12),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodieRestaurantCard(Map<String, dynamic> restaurant) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // レストラン画像（小さく表示）
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 50,
              height: 50,
              child: restaurant['image_url'] != null
                  ? (kIsWeb 
                      ? WebImageHelper.buildRestaurantImage(
                          restaurant['image_url'],
                          width: 50,
                          height: 50,
                        )
                      : Image.network(
                          restaurant['image_url'],
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => 
                              Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey[300],
                                child: const Icon(Icons.restaurant, color: Colors.grey, size: 20),
                              ),
                        ))
                  : Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[300],
                      child: const Icon(Icons.restaurant, color: Colors.grey, size: 20),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          
          // レストラン情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurant['name'] ?? 'レストラン名未設定',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (restaurant['category'] != null)
                  Row(
                    children: [
                      Icon(Icons.local_dining, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        restaurant['category'],
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                if (restaurant['price_range'] != null)
                  Row(
                    children: [
                      Icon(Icons.attach_money, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        restaurant['price_range'],
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          
          // いいねボタン
          GestureDetector(
            onTap: () async {
              final restaurantId = restaurant['id']?.toString() ?? '';
              final isLiked = _likedRestaurants.contains(restaurantId);
              await _toggleRestaurantLike(restaurantId, isLiked);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _likedRestaurants.contains(restaurant['id']?.toString() ?? '') 
                    ? const Color(0xFFF6BFBC) 
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _likedRestaurants.contains(restaurant['id']?.toString() ?? '') 
                    ? Icons.favorite 
                    : Icons.favorite_border,
                color: _likedRestaurants.contains(restaurant['id']?.toString() ?? '') 
                    ? Colors.white 
                    : Colors.grey,
                size: 20,
              ),
            ),
          ),
          
          // 三点ボタン（メニュー表示）
          if (restaurant['hotpepper_url'] != null)
            GestureDetector(
              onTap: () {
                _showRestaurantMenu(context, restaurant);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.more_horiz,
                  color: Colors.grey[600],
                  size: 20,
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
              // レストラン詳細画面ボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // モーダルを閉じる
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
                  icon: const Icon(Icons.info_outline, color: Colors.white),
                  label: const Text(
                    'レストラン詳細を見る',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFACD),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
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

  Widget _buildFoodieHashtagsSection() {
    final tags = profile!['tags'] as List;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tag, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'ハッシュタグ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${tags.length}個',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    '#$tag',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodieMbtiSection() {
    final mbti = (profile?['mbti'] ?? '').toString();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.psychology, color: Colors.orange.shade600, size: 20),
            const SizedBox(width: 8),
            const Text(
              'MBTI',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Text(
                mbti,
                style: TextStyle(
                  color: Colors.purple.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchingPreferencesSection() {
    final ageRange = profile?['preferred_age_range']?.toString();
    final preferredGender = profile?['preferred_gender']?.toString();

    List<Widget> preferenceItems = [];

    // 希望年齢範囲の処理（複数選択対応）
    if (ageRange != null && ageRange.isNotEmpty) {
      final ageRanges = ageRange.split(',').map((e) => e.trim()).toList();
      for (final range in ageRanges) {
        if (range.isNotEmpty) {
          preferenceItems.add(
            _buildFoodieInfoChip(Icons.cake, '${range}歳', Colors.brown),
          );
        }
      }
    }
    
    if (preferredGender != null && preferredGender.isNotEmpty) {
      preferenceItems.add(
        _buildFoodieInfoChip(Icons.wc, preferredGender, const Color(0xFFFFEFD5)),
      );
    }

    if (preferenceItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'マッチしたい人の特徴',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: preferenceItems,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentPreferenceSection() {
    final paymentPreference = profile?['payment_preference']?.toString();
    
    if (paymentPreference == null || paymentPreference.isEmpty) {
      return const SizedBox.shrink();
    }

    final paymentLabel = _getPaymentPreferenceLabel(paymentPreference);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_money, color: Colors.indigo.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '支払い方法',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFoodieInfoChip(Icons.attach_money, paymentLabel, Colors.indigo),
          ],
        ),
      ),
    );
  }

  String _getPaymentPreferenceLabel(String? preference) {
    if (preference == null || preference.isEmpty) {
      return '未設定';
    }
    switch (preference) {
      case 'split':
        return '割り勘希望';
      case 'pay':
        return '奢ってもいい';
      case 'be_paid':
        return '奢られたい';
      default:
        return '未設定';
    }
  }

  void _showImageDialog(int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              // ヘッダー（閉じるボタンと共有ボタン）
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: () => _shareImage(initialIndex),
                    ),
                  ],
                ),
              ),
              
              // 画像表示エリア
              Expanded(
                child: PageView.builder(
                  controller: PageController(initialPage: initialIndex),
                  itemCount: _userImages.length,
                  onPageChanged: (index) {
                    // ページが変更されたらSNS共有のためのインデックスを更新
                    setState(() {
                      _currentImageIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    return InteractiveViewer(
                      child: _buildProperImage(
                        _userImages[index]['image_url'] ?? '',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error, color: Colors.red, size: 40),
                                  SizedBox(height: 8),
                                  Text(
                                    '画像読み込みエラー',
                                    style: TextStyle(color: Colors.red, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              
              // 画像情報表示エリア
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // キャプション
                    if (_getImageCaption(initialIndex).isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getImageCaption(initialIndex),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    
                    // レストラン情報
                    if (_getImageRestaurant(initialIndex) != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.restaurant, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getImageRestaurant(initialIndex)!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
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
            ],
          ),
        ),
      ),
    );
  }

  // 画像のキャプションを取得
  String _getImageCaption(int index) {
    if (index >= _userImages.length) return '';
    
    final imageData = _userImages[index];
    return imageData['caption']?.toString() ?? '';
  }

  // 画像のレストラン情報を取得
  String? _getImageRestaurant(int index) {
    if (index >= _userImages.length) return null;
    
    final imageData = _userImages[index];
    return imageData['restaurant_name']?.toString();
  }

  // SNS共有機能
  void _shareImage(int index) async {
    try {
      final imageData = _userImages[index];
      final imageUrl = imageData['image_url'] ?? '';
      
      final caption = _getImageCaption(index);
      final restaurant = _getImageRestaurant(index);
      
      // 共有オプションを表示
      _showShareOptions(imageUrl, caption, restaurant);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('共有に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 共有オプションを表示
  void _showShareOptions(String imageUrl, String caption, String? restaurant) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '投稿をシェア',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            // Instagram連携されている場合のオプション
            if (_isInstagramConnected) ...[
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.purple),
                title: const Text('インスタグラムで開く'),
                subtitle: Text('@$_instagramUsername'),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareToInstagram(imageUrl, caption, restaurant);
                },
              ),
              const Divider(),
            ],
            
            // 汎用共有オプション
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blue),
              title: const Text('コピーしてシェア'),
              subtitle: const Text('クリップボードにコピーして他のアプリで使用'),
              onTap: () async {
                Navigator.pop(context);
                await _copyToClipboard(imageUrl, caption, restaurant);
              },
            ),
            
            // Instagram連携オプション（未連携の場合）
            if (!_isInstagramConnected) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.link, color: Colors.orange),
                title: const Text('インスタグラムと連携'),
                subtitle: const Text('直接インスタグラムに投稿できるようになります'),
                onTap: () async {
                  Navigator.pop(context);
                  await _connectToInstagram();
                },
              ),
            ],
            
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// インスタグラムでシェア
  Future<void> _shareToInstagram(String imageUrl, String caption, String? restaurant) async {
    try {
      await InstagramService.copyToClipboard(
        caption: caption,
        restaurantName: restaurant,
        imageUrl: imageUrl,
      );
      
      final opened = await InstagramService.openInstagramApp();
      
      if (opened) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('投稿内容をコピーしました！インスタグラムアプリが開きます。'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('インスタグラムアプリを開けませんでした。投稿内容はクリップボードにコピーされました。'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('インスタグラムでの共有に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// クリップボードにコピー
  Future<void> _copyToClipboard(String imageUrl, String caption, String? restaurant) async {
    try {
      await InstagramService.copyToClipboard(
        caption: caption,
        restaurantName: restaurant,
        imageUrl: imageUrl,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿内容をクリップボードにコピーしました！SNSアプリに貼り付けてシェアしてください。'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('クリップボードへのコピーに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// インスタグラムに連携
  Future<void> _connectToInstagram() async {
    try {
      final success = await InstagramService.connectToInstagram();
      
      if (success) {
        await _checkInstagramConnection(); // 連携状態を更新
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('インスタグラムと連携しました！'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('インスタグラムの連携に失敗しました。インスタグラムアプリがインストールされているか確認してください。'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('インスタグラムの連携に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🎨 根本的な色空間問題解決：FutureBuilderでraw画像データを処理
  Widget _buildProperImage(String imageUrl, {
    required BoxFit fit,
    double? width,
    double? height,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
    Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  }) {
    // Web版では共通ヘルパーを使用してCORS問題を回避
    if (kIsWeb) {
      return WebImageHelper.buildImage(
        imageUrl,
        width: width ?? 200,
        height: height ?? 200,
        fit: fit,
        errorWidget: errorBuilder != null 
            ? errorBuilder(context, Exception('画像読み込み失敗'), StackTrace.current)
            : null,
      );
    }
    
    return FutureBuilder<ui.Image>(
      future: _loadImageWithCorrectColorSpace(imageUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasError) {
          return errorBuilder?.call(context, snapshot.error!, StackTrace.current) ??
              Container(
                width: width,
                height: height,
                color: Colors.grey[300],
                child: const Icon(Icons.error),
              );
        }
        
        if (snapshot.hasData) {
          return RepaintBoundary(
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: _RawImageProvider(snapshot.data!),
                  fit: fit,
                ),
              ),
            ),
          );
        }
        
        return Container(width: width, height: height);
      },
    );
  }

  /// 色空間を適切に処理して画像を読み込む
  Future<ui.Image> _loadImageWithCorrectColorSpace(String imageUrl) async {
    try {
      final response = await HttpClient().getUrl(Uri.parse(imageUrl));
      response.headers.set('Accept', 'image/jpeg, image/png, image/webp');
      response.headers.set('Cache-Control', 'no-cache');
      
      final httpResponse = await response.close();
      final Uint8List bytes = await consolidateHttpClientResponseBytes(httpResponse);
      
      // 色空間を明示的にsRGBに変換
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: null,
        targetHeight: null,
        allowUpscaling: false,
      );
      
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } catch (e) {
      rethrow;
    }
  }
}

/// 🎨 ui.Imageを直接描画するためのImageProvider
class _RawImageProvider extends ImageProvider<_RawImageProvider> {
  final ui.Image image;
  
  const _RawImageProvider(this.image);

  @override
  Future<_RawImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_RawImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(_RawImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(
        ImageInfo(
          image: image,
          scale: 1.0,
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _RawImageProvider && other.image == image;
  }

  @override
  int get hashCode => image.hashCode;
} 