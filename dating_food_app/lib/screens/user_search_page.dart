import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/block_service.dart';
import '../services/web_image_helper.dart';
import 'profile_view_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 追加

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final TextEditingController _nameController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  int _totalCount = 0;
  
  // ページネーション用の変数
  int _currentLimit = 20;
  final int _maxLimit = 50;
  final int _incrementLimit = 10;
  
  // LIKE機能
  Set<String> _likedUsers = {};
  
  // 自分の学校情報（身内バレ防止用）
  String? _mySchoolId;
  
  // フィルター用の変数
  int? _minAge;
  int? _maxAge;
  List<String> _selectedGenders = [];
  List<String> _selectedOccupations = [];
  bool? _weekendOff;
  List<String> _selectedFavoriteCategories = [];
  bool? _idVerified;
  List<String> _selectedTags = [];
  String? _selectedMbti; // MBTIフィルター追加
  List<String> _selectedSchools = []; // 学校フィルター追加
  String? _myUserId;
  Set<String> _blockedUserIds = {};
  
  // 学校検索関連
  List<Map<String, dynamic>> _schoolSearchResults = [];
  bool _isSearchingSchools = false;
  final TextEditingController _schoolSearchController = TextEditingController();
  
  // 固定オプション
  static const List<String> _genders = ['男性', '女性', 'その他'];
  
  static const List<String> _occupations = [
    '会社員', 'エンジニア', '医療従事者', '教育関係', '公務員', 
    'フリーランス', '学生', 'その他'
  ];
  
  // 学校リスト（実際のデータベースから取得することを推奨）
  static const List<String> _schools = [
    '東京大学', '京都大学', '大阪大学', '名古屋大学', '東北大学',
    '九州大学', '北海道大学', '東京工業大学', '一橋大学', '東京医科歯科大学',
    '早稲田大学', '慶應義塾大学', '上智大学', '明治大学', '青山学院大学',
    '立教大学', '中央大学', '法政大学', '学習院大学', '東京理科大学',
    '日本大学', '東洋大学', '駒澤大学', '専修大学', '国士舘大学',
    'その他'
  ];

  static const List<String> _categories = [
    '居酒屋', 'カラオケ・パーティ', 'バー・カクテル', 'ラーメン', '和食', '韓国料理',
    'カフェ・スイーツ', '焼肉・ホルモン', 'アジア・エスニック料理', '洋食', '中華',
    'ダイニングバー・バル', 'イタリアン・フレンチ', 'その他グルメ', 'お好み焼き・もんじゃ',
    '各国料理', '創作料理',
  ];

  // MBTI選択肢
  static const List<String> _mbtiTypes = [
    'INTJ', 'INTP', 'ENTJ', 'ENTP',
    'INFJ', 'INFP', 'ENFJ', 'ENFP',
    'ISTJ', 'ISFJ', 'ESTJ', 'ESFJ',
    'ISTP', 'ISFP', 'ESTP', 'ESFP',
  ];

  // ハッシュタグの選択肢（添付リストに差し替え）
  static const List<String> _restaurantTags = [ '寿司好き', '焼肉好き', 'ラーメン好き', 'カフェ好き', 'パスタ好き', 'ピザ好き', 'スイーツ好き', 'パン好き', '和食好き', 'フレンチ好き',
'イタリアン好き', '中華好き', '韓国料理好き', 'タイ料理好き', 'ベトナム料理好き', 'インド料理好き', 'ステーキ好き', 'ハンバーガー好き', '鍋好き', 'しゃぶしゃぶ好き',
'お好み焼き好き', 'たこ焼き好き', '餃子好き', '天ぷら好き', 'うどん好き', 'そば好き', 'カレー好き', 'バル好き', 'ビストロ好き', '居酒屋好き',
'焼き鳥好き', '海鮮好き', '牡蠣好き', 'うなぎ好き', 'もつ鍋好き', 'ジビエ好き', '辛いの好き', 'チーズ好き', 'チョコレート好き', 'フルーツ好き', 'アイス好き',
'抹茶スイーツ好き', 'パフェ好き', 'クレープ好き', '和菓子好き', '洋菓子好き', 'コーヒー好き', '紅茶好き', '日本酒好き', 'ワイン好き', 'ビール好き',
'カクテル好き', 'ノンアルコール好き', '食べ歩き好き', '食べ放題好き', '飲み放題好き', '新しいお店行ってみたい', '人気店行ってみたい', '隠れ家行ってみたい', '老舗行ってみたい', '高級店行ってみたい',
'リーズナブルなお店好き', 'デートで行きたい', '女子会で行きたい', '男子会で行きたい', '合コンで行きたい', 'ファミリーで行きたい', '子連れOKなお店好き', 'ペット可のお店好き', 'テイクアウト好き', 'デリバリー好き', '朝食好き', 'ランチ好き',
'ディナー好き', '深夜営業のお店好き', '予約できるお店好き', 'カウンター席好き', 'ソファ席好き', '静かなお店好き', '賑やかなお店好き', 'オーガニック料理好き', 'ヘルシー料理好き', 'グルテンフリー好き',
'ベジタリアン料理好き', 'ヴィーガン料理好き', '世界の料理好き', 'ご当地グルメ好き', 'B級グルメ好き', '屋台グルメ好き', 'フードフェス好き', '期間限定メニュー好き', '季節限定メニュー好き', '新作メニュー好き',
'テイスティング好き', '食レポ好き', '料理写真撮るの好き', '料理動画撮るの好き', '料理教室行ってみたい', 'シェフと話したい', '食文化に興味あり', '食材にこだわりあり', '産地直送好き', '地元グルメ好き' ];
  static const List<String> _hobbyTags = [ '映画好き', '音楽好き', 'カラオケ好き', '読書好き', '漫画好き', 'アニメ好き', 'ゲーム好き', 'スポーツ観戦好き', 'サッカー好き', '野球好き',
'バスケ好き', 'テニス好き', 'バドミントン好き', '卓球好き', 'ゴルフ好き', 'ボウリング好き', 'ランニング好き', 'ジョギング好き', 'ウォーキング好き', '筋トレ好き',
'ヨガ好き', 'ピラティス好き', 'ダンス好き', '水泳好き', 'サイクリング好き', '登山好き', 'キャンプ好き', 'バーベキュー好き', '釣り好き', 'ドライブ好き',
'旅行好き', '国内旅行好き', '海外旅行好き', '温泉好き', '美術館好き', '博物館好き', 'カフェ巡り好き', '食べ歩き好き', '写真好き', '動画撮影好き',
'料理好き', 'お菓子作り好き', 'ガーデニング好き', 'DIY好き', '手芸好き', 'イラスト好き', '絵画好き', 'ピアノ好き', 'ギター好き', 'バイオリン好き',
'カメラ好き', 'プラモデル好き', '鉄道好き', 'バイク好き', '車好き', 'ファッション好き', 'コスメ好き', 'メイク好き', 'ネイル好き', 'ショッピング好き',
'アウトドア好き', 'インドア好き', '動物好き', '犬好き', '猫好き', '水族館好き', '動物園好き', 'フェス好き', 'ライブ好き', 'コンサート好き',
'ボードゲーム好き', 'カードゲーム好き', 'マジック好き', 'クイズ好き', '謎解き好き', '脱出ゲーム好き', 'サウナ好き', 'スパ好き', 'マッサージ好き', '占い好き',
'英会話やってみたい', '語学学習やってみたい', '勉強好き', '投資やってみたい', '資格取得やってみたい', 'ボランティアやってみたい', '子育て中', '家庭菜園やってみたい', 'サーフィンやってみたい', 'スキーやってみたい',
'スノーボードやってみたい', 'スケートやってみたい', 'フィットネス好き', 'eスポーツ好き', 'VR体験やってみたい', 'プログラミングやってみたい', 'ブログやってみたい', 'SNS好き', 'YouTubeやってみたい', 'ポッドキャスト好き' ];
  static const List<String> _personalityTags = [ '明るい', '積極的', 'おとなしい', '優しい', '面白い', '真面目', '誠実', '素直', 'ポジティブ', 'ネガティブ',
'おおらか', '繊細', 'マイペース', '几帳面', '大雑把', '責任感が強い', '向上心がある', '好奇心旺盛', '人見知り', '社交的',
'リーダータイプ', 'サポートタイプ', '聞き上手', '話し上手', 'おしゃべり', '無口', 'ロマンチスト', '現実主義', '計画的', '行動派',
'慎重', '楽観的', '悲観的', '頑張り屋', '努力家', 'こだわりが強い', '柔軟', '忍耐強い', '短気', 'おっとり',
'せっかち', 'のんびり', '笑い上戸', '泣き上戸', 'お酒好き', 'お酒弱い', '甘えん坊', 'しっかり者', '天然', '自立心が強い',
'家族思い', '友達思い', '負けず嫌い', 'お人好し', 'サバサバ', 'さっぱり', 'こだわり派', 'クリエイティブ', '論理的', '感情的',
'大胆', '直感型', '計画型', '目立ちたがり', '控えめ', 'おしゃれ', 'シンプル好き', '新しいもの好き', '古風', '伝統好き',
'冒険好き', '安定志向', 'チャレンジ精神', '競争心が強い', '協調性がある', '一途', '浮気性', '恋愛体質', '恋愛に奥手', '恋愛積極的',
'恋愛慎重', '家庭的', '仕事熱心', '趣味多彩', '一人好き', 'みんなでワイワイ', 'お世話好き', '癒し系', '冷静', '情熱的',
'ユーモアがある', '気配り上手', '空気が読める', '相談されやすい', 'まとめ役', '影の努力家', '直感が鋭い', '物事に動じない', '目標志向', '夢追い人' ];

  static Map<String, List<String>> get _hashtagCategories => {
    'レストラン': _restaurantTags,
    '趣味': _hobbyTags,
    '性格': _personalityTags,
  };

  late final SupabaseClient _supabase;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _initializeDataSequentially();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _schoolSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeDataSequentially() async {
    // 1. まず自分のIDとブロック情報を取得
    await _initializeUserIdAndBlocks();
    
    // 2. その後で初期データを取得
    await _initializeData();
  }

  Future<void> _initializeUserIdAndBlocks() async {
    // Supabase Authの初期化を待つ
    await Future.delayed(const Duration(milliseconds: 500));
    
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      // Firebase AuthからUIDを取得
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          // Firebase UIDを使ってusersテーブルから自分のIDと学校情報を取得
          final userResult = await _supabase
              .from('users')
              .select('id, school_id')
              .eq('firebase_uid', firebaseUser.uid)
              .single();
          
          _myUserId = userResult['id'];
          _mySchoolId = userResult['school_id'];
          
          if (_myUserId != null) {
            // ブロック情報を取得（既存の処理を再利用）
            final blockRows = await _supabase
                .from('user_blocks')
                .select('blocker_id, blocked_id')
                .or('blocker_id.eq.$_myUserId,blocked_id.eq.$_myUserId');
            
            final blockedIds = <String>{};
            for (final row in blockRows) {
              if (row['blocker_id'] == _myUserId) {
                blockedIds.add(row['blocked_id']);
              } else if (row['blocked_id'] == _myUserId) {
                blockedIds.add(row['blocker_id']);
              }
            }
            
            if (mounted) {
              setState(() {
                _blockedUserIds = blockedIds;
              });
            }
          }
        } catch (e) {
          // エラー処理
        }
      }
      return;
    }
    
    try {
      print('🔍 usersテーブルから自分のIDと学校情報を取得中...');
      // 自分のusersテーブルのIDと学校情報を取得
      final userResult = await _supabase
          .from('users')
          .select('id, school_id')
          .eq('firebase_uid', currentUser.id)
          .single();
      
      _myUserId = userResult['id'];
      _mySchoolId = userResult['school_id'];
      if (_myUserId == null) return;
      
      // user_blocksテーブルから自分が関係するブロック情報を取得
      final blockRows = await _supabase
          .from('user_blocks')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$_myUserId,blocked_id.eq.$_myUserId');
      
      final blockedIds = <String>{};
      for (final row in blockRows) {
        if (row['blocker_id'] == _myUserId) {
          blockedIds.add(row['blocked_id']);
        } else if (row['blocked_id'] == _myUserId) {
          blockedIds.add(row['blocker_id']);
        }
      }
      
      if (mounted) {
        setState(() {
          _blockedUserIds = blockedIds;
        });
      }
    } catch (e) {
      // エラー処理
    }
  }

  // データキャッシュ
  static DateTime? _lastLoadTime;
  static List<dynamic> _cachedSearchResults = [];
  static Set<String> _cachedLikedUsers = {};
  static const Duration _cacheValidDuration = Duration(minutes: 3);

  Future<void> _initializeData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      // 初期表示: Supabaseから最新ユーザー20件取得
      final result = await _supabase
          .from('users')
          .select('id, name, image_url, age, occupation, gender, favorite_categories, weekend_off, id_verified, mbti, tags, school_name, school_type, school_id, hide_from_same_school, visible_only_if_liked')
          .order('created_at', ascending: false)
          .limit(20);
      
      // 自分自身、ブロック関係、プライバシー設定ユーザーを除外
      final filteredResults = result.where((user) {
        final userId = user['id'];
        
        // 自分自身を除外
        if (_myUserId != null && userId == _myUserId) return false;
        
        // ブロック関係を除外
        if (_blockedUserIds.contains(userId)) return false;
        
        // 身内バレ防止機能: 相手がhide_from_same_school = trueかつ同じ学校の場合は除外
        if (user['hide_from_same_school'] == true && 
            _mySchoolId != null && 
            user['school_id'] != null &&
            _mySchoolId == user['school_id']) {
          return false;
        }
        
        // いいね限定表示機能: 相手がvisible_only_if_liked = trueかつ自分がいいねしていない場合は除外
        if (user['visible_only_if_liked'] == true && 
            !_likedUsers.contains(userId)) {
          return false;
        }
        
        return true;
      }).toList();
      
      setState(() {
        _searchResults = filteredResults;
        _totalCount = filteredResults.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
    }
  }
  
     // 背景でいいね状態を読み込み
   Future<void> _loadUserLikesInBackground() async {
     try {
       await _loadUserLikes().timeout(const Duration(seconds: 2));
       _cachedLikedUsers = Set.from(_likedUsers);
     } catch (e) {
     }
   }

   // リフレッシュ時のデータ更新（キャッシュクリア付き）
   Future<void> _refreshData() async {
     
     // キャッシュをクリア
     _lastLoadTime = null;
     _cachedSearchResults.clear();
     _cachedLikedUsers.clear();
     
     // データを再取得
     await _searchUsers();
   }

  Future<void> _searchUsers({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _currentLimit = 15;
      });
    }
    try {
      var query = _supabase
          .from('users')
          .select('id, name, image_url, age, occupation, gender, favorite_categories, weekend_off, id_verified, mbti, tags, school_name, school_type, school_id, hide_from_same_school, visible_only_if_liked');
      // 名前検索
      if (_nameController.text.isNotEmpty) {
        query = query.ilike('name', '%${_nameController.text}%');
      }
      // 年齢フィルター
      if (_minAge != null) {
        query = query.gte('age', _minAge as Object);
      }
      if (_maxAge != null) {
        query = query.lte('age', _maxAge as Object);
      }
      // 性別フィルター
      if (_selectedGenders.isNotEmpty) {
        query = query.inFilter('gender', _selectedGenders);
      }
      // 職業フィルター
      if (_selectedOccupations.isNotEmpty) {
        query = query.inFilter('occupation', _selectedOccupations);
      }
      // 休日フィルター
      if (_weekendOff != null) {
        query = query.eq('weekend_off', _weekendOff as Object);
      }
      // 好みのカテゴリーフィルター
      if (_selectedFavoriteCategories.isNotEmpty) {
        query = query.contains('favorite_categories', _selectedFavoriteCategories);
      }
      // 本人確認フィルター
      if (_idVerified != null) {
        query = query.eq('id_verified', _idVerified as Object);
      }
      // MBTIフィルター
      if (_selectedMbti != null) {
        query = query.eq('mbti', _selectedMbti as Object);
      }
      // ハッシュタグフィルター
      if (_selectedTags.isNotEmpty) {
        query = query.contains('tags', _selectedTags);
      }
      // 学校フィルター
      if (_selectedSchools.isNotEmpty) {
        query = query.inFilter('school_id', _selectedSchools);
      }
      final result = await query.limit(_currentLimit);
      
      // 自分自身、ブロック関係、プライバシー設定ユーザーを除外
      final filteredResults = result.where((user) {
        final userId = user['id'];
        
        // 自分自身を除外
        if (_myUserId != null && userId == _myUserId) return false;
        
        // ブロック関係を除外
        if (_blockedUserIds.contains(userId)) return false;
        
        // 身内バレ防止機能: 相手がhide_from_same_school = trueかつ同じ学校の場合は除外
        if (user['hide_from_same_school'] == true && 
            _mySchoolId != null && 
            user['school_id'] != null &&
            _mySchoolId == user['school_id']) {
          return false;
        }
        
        // いいね限定表示機能: 相手がvisible_only_if_liked = trueかつ自分がいいねしていない場合は除外
        if (user['visible_only_if_liked'] == true && 
            !_likedUsers.contains(userId)) {
          return false;
        }
        
        return true;
      }).toList();
      
      setState(() {
        _searchResults = filteredResults;
        _totalCount = filteredResults.length;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
    }
  }

  Future<void> _loadUserLikes() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 3));
      
      if (mounted) {
        setState(() {
          final sentLikes = List.from(result.data['sentLikes'] ?? []);
          _likedUsers = Set<String>.from(
            sentLikes.map((like) => like['liked_user_id']?.toString() ?? '').where((id) => id.isNotEmpty)
          );
        });
      }
    } catch (e) {
      // エラー時は空の状態を維持
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

    // いいね追加のUIを更新
    setState(() {
      _likedUsers.add(userId);
    });

    // バックグラウンドでAPI呼び出し
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('addUserLike');
      
      // タイムアウトを短く設定
      await callable({'likedUserId': userId}).timeout(const Duration(seconds: 5));
      
    } catch (e) {
      
      // エラー時のみUIを元に戻す
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
          // ブロックリストを更新して検索結果を再読み込み
          await _initializeUserIdAndBlocks();
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

  // ハッシュタグフィルターのダイアログを表示
  Future<void> _showHashtagFilterDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        List<String> tempSelection = List.from(_selectedTags);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ハッシュタグを選択'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _hashtagCategories.entries.map((entry) {
                    return ExpansionTile(
                      title: Text(entry.key),
                      children: ListTile.divideTiles(
                        context: context,
                        tiles: entry.value.map((tag) {
                          return CheckboxListTile(
                            title: Text(tag),
                            value: tempSelection.contains(tag),
                            onChanged: (bool? value) {
                              setDialogState(() {
                                if (value == true) {
                                  tempSelection.add(tag);
                                } else {
                                  tempSelection.remove(tag);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ).toList(),
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('クリア'),
                  onPressed: () {
                    setDialogState(() {
                      tempSelection.clear();
                    });
                  },
                ),
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
        _selectedTags = result;
      });
      _searchUsers();
    }
  }

  // 学校検索機能
  Future<void> _searchSchools(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _schoolSearchResults = [];
        _isSearchingSchools = false;
      });
      return;
    }

    setState(() {
      _isSearchingSchools = true;
    });

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('searchSchools');
      final result = await callable.call({
        'query': query.trim(),
        'limit': 20,
      });

      if (mounted) {
        setState(() {
          _schoolSearchResults = List<Map<String, dynamic>>.from(
            result.data['schools'] ?? []
          );
          _isSearchingSchools = false;
        });
      }
    } catch (e) {
      print('学校検索エラー: $e');
      if (mounted) {
        setState(() {
          _schoolSearchResults = [];
          _isSearchingSchools = false;
        });
      }
    }
  }

  // ダイアログ内での学校検索機能
  Future<void> _searchSchoolsInDialog(String query, Function setDialogState) async {
    if (query.trim().length < 2) {
      setDialogState(() {
        _schoolSearchResults = [];
        _isSearchingSchools = false;
      });
      return;
    }

    setDialogState(() {
      _isSearchingSchools = true;
    });

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('searchSchools');
      final result = await callable.call({
        'query': query.trim(),
        'limit': 20,
      });

      setDialogState(() {
        _schoolSearchResults = List<Map<String, dynamic>>.from(
          result.data['schools'] ?? []
        );
        _isSearchingSchools = false;
      });
    } catch (e) {
      print('学校検索エラー: $e');
      setDialogState(() {
        _schoolSearchResults = [];
        _isSearchingSchools = false;
      });
    }
  }

  // 学校選択
  void _selectSchool(Map<String, dynamic> school) {
    setState(() {
      _selectedSchools.add(school['id']);
      _schoolSearchController.text = school['display_name'] ?? school['school_name'];
      _schoolSearchResults = [];
      _isSearchingSchools = false;
    });
    _searchUsers();
  }

  // 学校選択をクリア
  void _clearSchoolSelection() {
    setState(() {
      _selectedSchools.clear();
      _schoolSearchController.clear();
      _schoolSearchResults = [];
      _isSearchingSchools = false;
    });
    _searchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザー検索'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        leading: kIsWeb ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ) : null,
      ),
      body: Column(
        children: [
          // 検索バー
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '名前で検索',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
              ),
              onSubmitted: (_) => _searchUsers(),
            ),
          ),

          // フィルターエリア
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // 年齢フィルター
                FilterChip(
                  label: Text(
                    _minAge == null && _maxAge == null
                        ? '年齢'
                        : '${_minAge ?? ''}〜${_maxAge ?? ''}歳',
                  ),
                  selected: _minAge != null || _maxAge != null,
                  onSelected: (_) async {
                    final result = await showDialog<Map<String, int?>>(
                      context: context,
                      builder: (BuildContext context) {
                        int? tempMin = _minAge;
                        int? tempMax = _maxAge;
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                        return AlertDialog(
                              title: const Text('年齢を設定'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                    decoration: const InputDecoration(
                                      labelText: '最小年齢',
                                      border: OutlineInputBorder(),
                                    ),
                                keyboardType: TextInputType.number,
                                    controller: TextEditingController(
                                      text: tempMin?.toString() ?? '',
                                    ),
                                onChanged: (value) {
                                  tempMin = int.tryParse(value);
                                },
                                ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    decoration: const InputDecoration(
                                      labelText: '最大年齢',
                                      border: OutlineInputBorder(),
                              ),
                                keyboardType: TextInputType.number,
                                    controller: TextEditingController(
                                      text: tempMax?.toString() ?? '',
                                    ),
                                onChanged: (value) {
                                  tempMax = int.tryParse(value);
                                },
                              ),
                            ],
                          ),
                          actions: [
                                TextButton(
                                  child: const Text('クリア'),
                                  onPressed: () {
                                    Navigator.of(context).pop({'min': null, 'max': null});
                                  },
                                ),
                            TextButton(
                              child: const Text('キャンセル'),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            TextButton(
                              child: const Text('OK'),
                              onPressed: () {
                                    Navigator.of(context).pop({'min': tempMin, 'max': tempMax});
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
                        _minAge = result['min'];
                        _maxAge = result['max'];
                      });
                      _searchUsers();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 性別フィルター
                FilterChip(
                  label: Text(
                    _selectedGenders.isEmpty ? '性別' : _selectedGenders.join(', '),
                  ),
                  selected: _selectedGenders.isNotEmpty,
                  onSelected: (_) async {
                    final result = await showDialog<List<String>>(
                      context: context,
                      builder: (BuildContext context) {
                        List<String> tempSelection = List.from(_selectedGenders);
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                        return AlertDialog(
                          title: const Text('性別を選択'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _genders.map((gender) {
                              return CheckboxListTile(
                                title: Text(gender),
                                value: tempSelection.contains(gender),
                                onChanged: (bool? value) {
                                      setDialogState(() {
                                  if (value == true) {
                                    tempSelection.add(gender);
                                  } else {
                                    tempSelection.remove(gender);
                                  }
                                      });
                                },
                              );
                            }).toList(),
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
                        _selectedGenders = result;
                      });
                      _searchUsers();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 職業フィルター
                FilterChip(
                  label: Text(
                    _selectedOccupations.isEmpty
                        ? '職業'
                        : _selectedOccupations.join(', '),
                  ),
                  selected: _selectedOccupations.isNotEmpty,
                  onSelected: (_) async {
                    final result = await showDialog<List<String>>(
                      context: context,
                      builder: (BuildContext context) {
                        List<String> tempSelection =
                            List.from(_selectedOccupations);
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                        return AlertDialog(
                          title: const Text('職業を選択'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: _occupations.map((occupation) {
                                return CheckboxListTile(
                                  title: Text(occupation),
                                  value: tempSelection.contains(occupation),
                                  onChanged: (bool? value) {
                                        setDialogState(() {
                                    if (value == true) {
                                      tempSelection.add(occupation);
                                    } else {
                                      tempSelection.remove(occupation);
                                    }
                                        });
                                  },
                                );
                              }).toList(),
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
                        _selectedOccupations = result;
                      });
                      _searchUsers();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 休日フィルター
                FilterChip(
                  label: Text(_weekendOff == null ? '休日' : '土日休み'),
                  selected: _weekendOff == true,
                  onSelected: (bool selected) {
                    setState(() {
                      _weekendOff = selected ? true : null;
                    });
                    _searchUsers();
                  },
                ),
                const SizedBox(width: 8),

                // 好みのカテゴリーフィルター
                FilterChip(
                  label: Text(
                    _selectedFavoriteCategories.isEmpty
                        ? '好みのカテゴリー'
                        : _selectedFavoriteCategories.join(', '),
                  ),
                  selected: _selectedFavoriteCategories.isNotEmpty,
                  onSelected: (_) async {
                    final result = await showDialog<List<String>>(
                      context: context,
                      builder: (BuildContext context) {
                        List<String> tempSelection =
                            List.from(_selectedFavoriteCategories);
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                        return AlertDialog(
                          title: const Text('好みのカテゴリーを選択'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: _categories.map((category) {
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
                              }).toList(),
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
                        _selectedFavoriteCategories = result;
                      });
                      _searchUsers();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // 本人確認フィルター
                FilterChip(
                  label: Text(_idVerified == null ? '本人確認' : '本人確認済み'),
                  selected: _idVerified == true,
                  onSelected: (bool selected) {
                    setState(() {
                      _idVerified = selected ? true : null;
                    });
                    _searchUsers();
                  },
                ),
                const SizedBox(width: 8),

                // MBTIフィルター
                FilterChip(
                  label: Text(_selectedMbti == null ? 'MBTI' : _selectedMbti!),
                  selected: _selectedMbti != null,
                  onSelected: (_) async {
                    final result = await showDialog<String>(
                      context: context,
                      builder: (BuildContext context) {
                        String? tempMbti = _selectedMbti;
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                            return AlertDialog(
                              title: const Text('MBTIを選択'),
                              content: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _mbtiTypes.map((mbti) {
                                    return ChoiceChip(
                                      label: Text(mbti),
                                      selected: tempMbti == mbti,
                                      onSelected: (selected) {
                                        setDialogState(() {
                                          tempMbti = selected ? mbti : null;
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  child: const Text('クリア'),
                                  onPressed: () => Navigator.of(context).pop(null),
                                ),
                                TextButton(
                                  child: const Text('OK'),
                                  onPressed: () => Navigator.of(context).pop(tempMbti),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                    if (result != null || _selectedMbti != null) {
                      setState(() {
                        _selectedMbti = result;
                      });
                      _searchUsers();
                    }
                  },
                ),
                const SizedBox(width: 8),

                // ハッシュタグフィルター
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilterChip(
                      label: Text(
                        _selectedTags.isEmpty ? 'ハッシュタグ' : '${_selectedTags.length}個選択',
                      ),
                      selected: _selectedTags.isNotEmpty,
                      onSelected: (_) => _showHashtagFilterDialog(),
                    ),
                    if (_selectedTags.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'クリア',
                        onPressed: () {
                          setState(() {
                            _selectedTags.clear();
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(width: 8),

                // 学校フィルター
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilterChip(
                      label: Text(
                        _selectedSchools.isEmpty ? '学校' : '${_selectedSchools.length}校選択',
                      ),
                      selected: _selectedSchools.isNotEmpty,
                      onSelected: (_) async {
                        // ダイアログを開く前に検索状態をリセット
                        _schoolSearchResults = [];
                        _isSearchingSchools = false;
                        
                        final result = await showDialog<void>(
                          context: context,
                          builder: (BuildContext context) {
                            return StatefulBuilder(
                              builder: (context, setDialogState) {
                                return AlertDialog(
                                  title: const Text('学校を検索・選択'),
                                  content: SizedBox(
                                    width: 400,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 学校検索フィールド
                                        TextField(
                                          controller: _schoolSearchController,
                                          decoration: InputDecoration(
                                            border: const OutlineInputBorder(),
                                            prefixIcon: const Icon(Icons.school),
                                            hintText: '学校名を入力して検索',
                                            suffixIcon: _selectedSchools.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(Icons.clear),
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      _selectedSchools.clear();
                                                      _schoolSearchController.clear();
                                                      _schoolSearchResults = [];
                                                      _isSearchingSchools = false;
                                                    });
                                                  },
                                                )
                                              : _isSearchingSchools
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : null,
                                          ),
                                          onChanged: (value) {
                                            _searchSchoolsInDialog(value, setDialogState);
                                          },
                                        ),
                                        
                                        const SizedBox(height: 16),
                                        
                                        // 検索結果表示
                                        if (_schoolSearchResults.isNotEmpty)
                                          Container(
                                            constraints: const BoxConstraints(maxHeight: 200),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: _schoolSearchResults.length,
                                              itemBuilder: (context, index) {
                                                final school = _schoolSearchResults[index];
                                                return ListTile(
                                                  title: Text(school['school_name']),
                                                  subtitle: Text(
                                                    '${school['type_label']} • ${school['establishment_label']} • ${school['prefecture_name']}'
                                                  ),
                                                  onTap: () {
                                                    _selectSchool(school);
                                                    Navigator.pop(context);
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                        
                                        // 選択済み学校の表示
                                        if (_selectedSchools.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          const Text(
                                            '選択済みの学校:',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: _selectedSchools.map((schoolId) {
                                              final school = _schoolSearchResults.firstWhere(
                                                (s) => s['id'] == schoolId,
                                                orElse: () => {'school_name': '不明な学校'},
                                              );
                                              return Chip(
                                                label: Text(school['school_name']),
                                                onDeleted: () {
                                                  setState(() {
                                                    _selectedSchools.remove(schoolId);
                                                  });
                                                  setDialogState(() {});
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      child: const Text('キャンセル'),
                                      onPressed: () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    if (_selectedSchools.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'クリア',
                        onPressed: () {
                          _clearSchoolSelection();
                        },
                      ),
                  ],
                ),
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
                        ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 64, color: Colors.grey),
                            SizedBox(height: 20),
                            Text(
                              '検索結果が見つかりません',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            SizedBox(height: 10),
                            Text('検索条件を変更してみてください'),
                          ],
                            ),
                          )
                        : ListView.builder(
                        itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final user = _searchResults[index];
                          final String userId = user['id'] ?? '';
                          final bool isLiked = _likedUsers.contains(userId);
                          final String userName = user['name'] ?? '名前未設定';

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: InkWell(
                                  onTap: () {
                                    if (userId.isNotEmpty) {
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 画像部分
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Container(
                                            width: 120,
                                            color: Colors.grey[300],
                                            child: AspectRatio(
                                              aspectRatio: 1.0,
                                              child: kIsWeb
                                                  ? WebImageHelper.buildProfileImage(
                                                      user['image_url'],
                                                      size: 120,
                                                      isCircular: false,
                                                    )
                                                  : user['image_url'] != null
                                                      ? Image.network(
                                                          user['image_url'],
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return const Icon(Icons.person, size: 60, color: Colors.grey);
                                                          },
                                                        )
                                                      : const Icon(Icons.person, size: 60, color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // テキスト情報部分
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                userName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                              const SizedBox(height: 4),
                                              Text('${user['age'] ?? '?'}歳 • ${user['gender'] ?? '未設定'}'),
                                              if (user['occupation'] != null) ...[
                                                const SizedBox(height: 4),
                                                Text('職業: ${user['occupation']}'),
                                              ],
                                              if (user['favorite_categories'] != null &&
                                                  user['favorite_categories'] is List &&
                                                  (user['favorite_categories'] as List).isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  '好みのカテゴリー: ${(user['favorite_categories'] as List).join(', ')}',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                              if (user['weekend_off'] == true) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  '土日休み',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                              if (user['id_verified'] == true) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.verified,
                                                      size: 16,
                                                      color: Colors.blue[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '本人確認済み',
                                                      style: TextStyle(
                                                        color: Colors.blue[600],
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              // ハッシュタグ表示
                                              if (user['tags'] != null &&
                                                  user['tags'] is List &&
                                                  (user['tags'] as List).isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 4,
                                                  runSpacing: 4,
                                                  children: (user['tags'] as List).take(15).map((tag) {
                                                    return Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.shade50,
                                                        borderRadius: BorderRadius.circular(12),
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
                                              // MBTI表示
                                              if (user['mbti'] != null && user['mbti'].toString().isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.purple.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.purple.shade200),
                                                  ),
                                                  child: Text(
                                                    'MBTI: ${user['mbti']}',
                                                    style: TextStyle(
                                                      color: Colors.purple.shade700,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // ボタン部分
                                        Column(
                                          children: [
                                            // 三点メニューボタン
                                            PopupMenuButton<String>(
                                              onSelected: (value) async {
                                                if (value == 'block' && userId.isNotEmpty) {
                                                  await _blockUser(userId, userName);
                                                }
                                              },
                                              itemBuilder: (BuildContext context) => [
                                                const PopupMenuItem<String>(
                                                  value: 'block',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.block, color: Colors.red, size: 18),
                                                      SizedBox(width: 8),
                                                      Text('ブロック'),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                child: const Icon(
                                                  Icons.more_vert,
                                                  size: 20,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // いいねボタン
                                            GestureDetector(
                                              onTap: () {
                                                _toggleUserLike(userId, isLiked);
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                child: Icon(
                                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                                  color: Colors.pink,
                                                  size: 24,
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
          ),
        ],
      ),
    );
  }
}