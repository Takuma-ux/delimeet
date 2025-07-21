import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/group_model.dart';
import '../services/group_service.dart';
import 'profile_view_page.dart';

class GroupMemberSearchPage extends StatefulWidget {
  final Group group;

  const GroupMemberSearchPage({
    Key? key,
    required this.group,
  }) : super(key: key);

  @override
  State<GroupMemberSearchPage> createState() => _GroupMemberSearchPageState();
}

class _GroupMemberSearchPageState extends State<GroupMemberSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final GroupService _groupService = GroupService();
  
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isInviting = false;
  String? _invitingUserId;
  int _totalCount = 0;

  // フィルター用の変数
  int? _minAge;
  int? _maxAge;
  List<String> _selectedGenders = [];
  List<String> _selectedOccupations = [];
  bool? _weekendOff;
  List<String> _selectedFavoriteCategories = [];
  bool? _idVerified;
  List<String> _selectedTags = [];
  
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
  
  // ハッシュタグの選択肢（ユーザー検索ページと同じ）
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

  @override
  void initState() {
    super.initState();
    // 初期検索を実行
    _searchUsers();
  }

  // 最新のグループ情報を取得する
  Future<Group> _getLatestGroupInfo() async {
    try {
      final group = await _groupService.getGroup(widget.group.id);
      return group ?? widget.group;
    } catch (e) {
      return widget.group;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    setState(() {
      _isSearching = true;
    });

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('searchUsers');
      
      // 検索パラメータの構築
      Map<String, dynamic> searchParams = {
        'limit': 50,
      };
      
      // 名前検索
      if (_searchController.text.isNotEmpty) {
        searchParams['keyword'] = _searchController.text;
      }
      
      // 年齢フィルター
      if (_minAge != null) searchParams['minAge'] = _minAge;
      if (_maxAge != null) searchParams['maxAge'] = _maxAge;
      
      // 性別フィルター
      if (_selectedGenders.isNotEmpty) {
        searchParams['genders'] = _selectedGenders;
      }
      
      // 職業フィルター
      if (_selectedOccupations.isNotEmpty) {
        searchParams['occupations'] = _selectedOccupations;
      }
      
      // 休日フィルター
      if (_weekendOff != null) {
        searchParams['weekendOff'] = _weekendOff;
      }
      
      // 好みのカテゴリーフィルター
      if (_selectedFavoriteCategories.isNotEmpty) {
        searchParams['favoriteCategories'] = _selectedFavoriteCategories;
      }
      
      // 本人確認フィルター
      if (_idVerified != null) {
        searchParams['idVerified'] = _idVerified;
      }
      
      // ハッシュタグフィルター
      if (_selectedTags.isNotEmpty) {
        searchParams['tags'] = _selectedTags;
      }

      final result = await callable.call(searchParams);

      if (result.data != null && result.data['users'] != null) {
        final users = List<Map<String, dynamic>>.from(
          result.data['users'].map((user) => Map<String, dynamic>.from(user))
        );
        
        for (int i = 0; i < users.length && i < 3; i++) {
          final user = users[i];
        }
        
        // 最新のグループ情報を取得
        final latestGroup = await _getLatestGroupInfo();
        
        // 現在のグループメンバーを除外（複数のIDフィールドに対応）
        final filteredUsers = users.where((user) {
          // 複数のIDフィールドをチェック
          final userIds = [
            user['id']?.toString(),
            user['uid']?.toString(),
            user['firebase_uid']?.toString(),
            user['user_id']?.toString(),
          ].where((id) => id != null && id.isNotEmpty).toSet();
          
          // いずれかのIDがグループメンバーに含まれているかチェック
          final isAlreadyMember = userIds.any((userId) => latestGroup.members.contains(userId));
          
          if (isAlreadyMember) {
          }
          return !isAlreadyMember;
        }).toList();

        for (int i = 0; i < filteredUsers.length && i < 3; i++) {
          final user = filteredUsers[i];
        }

        setState(() {
          _searchResults = filteredUsers;
          _totalCount = result.data['totalCount'] ?? 0;
        });
      } else {
        setState(() {
          _searchResults = [];
          _totalCount = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('検索に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _inviteUser(String userId, String userName) async {
    
    setState(() {
      _isInviting = true;
      _invitingUserId = userId;
    });

    try {
      // グループ招待を送信
      await _groupService.inviteUserToGroup(widget.group.id, userId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName さんに招待を送信しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // 検索結果から削除
        setState(() {
          _searchResults.removeWhere((user) => user['id'] == userId);
        });
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '招待の送信に失敗しました';
        
        // エラーメッセージをユーザーフレンドリーに変換
        if (e.toString().contains('既に招待を送信済み')) {
          errorMessage = '既に招待を送信済みです';
        } else if (e.toString().contains('見つかりません')) {
          errorMessage = 'ユーザーが見つかりません';
        } else if (e.toString().contains('ネットワーク')) {
          errorMessage = 'ネットワークエラーが発生しました';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      setState(() {
        _isInviting = false;
        _invitingUserId = null;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _minAge = null;
      _maxAge = null;
      _selectedGenders.clear();
      _selectedOccupations.clear();
      _weekendOff = null;
      _selectedFavoriteCategories.clear();
      _idVerified = null;
      _selectedTags.clear();
    });
    _searchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 画面をタップしたときにキーボードを閉じる
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('メンバーを追加'),
          backgroundColor: Colors.pink[400],
          foregroundColor: Colors.white,
          actions: [
            // フィルタークリアボタン
            if (_hasActiveFilters())
              TextButton(
                onPressed: _clearFilters,
                child: const Text(
                  'クリア',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // 検索バー
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'ユーザー名で検索...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _searchUsers();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  // リアルタイム検索（デバウンス付き）
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_searchController.text == value) {
                      _searchUsers();
                    }
                  });
                },
                onSubmitted: (_) {
                  _searchUsers();
                  // 検索後にキーボードを閉じる
                  FocusScope.of(context).unfocus();
                },
                textInputAction: TextInputAction.search,
              ),
            ),

            // フィルターチップ
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // 年齢フィルター
                    FilterChip(
                      label: Text(
                        _minAge != null || _maxAge != null
                            ? '年齢: ${_minAge ?? ''}${_minAge != null && _maxAge != null ? '-' : ''}${_maxAge ?? ''}歳'
                            : '年齢',
                      ),
                      selected: _minAge != null || _maxAge != null,
                      onSelected: (_) => _showAgeFilterDialog(),
                    ),
                    const SizedBox(width: 8),

                    // 性別フィルター
                    FilterChip(
                      label: Text(
                        _selectedGenders.isEmpty
                            ? '性別'
                            : _selectedGenders.join(', '),
                      ),
                      selected: _selectedGenders.isNotEmpty,
                      onSelected: (_) => _showGenderFilterDialog(),
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
                      onSelected: (_) => _showOccupationFilterDialog(),
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
                      onSelected: (_) => _showCategoryFilterDialog(),
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
                              _searchUsers();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // 検索結果
            Expanded(
              child: _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _minAge != null ||
        _maxAge != null ||
        _selectedGenders.isNotEmpty ||
        _selectedOccupations.isNotEmpty ||
        _weekendOff != null ||
        _selectedFavoriteCategories.isNotEmpty ||
        _idVerified != null ||
        _selectedTags.isNotEmpty;
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty || _hasActiveFilters()
                  ? 'ユーザーが見つかりませんでした'
                  : 'ユーザー名を入力して検索してください',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 検索結果数表示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${_searchResults.length}件のユーザーが見つかりました',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        
        // ユーザーリスト
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final user = _searchResults[index];
              return _buildUserTile(user);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id'] as String;
          final userName = user['name'] ?? 'ユーザー';
    final userImageUrl = user['image_url'] ?? user['imageUrl'];
    final userAge = user['age']?.toString();
    final userPrefecture = user['prefecture'];
    final userOccupation = user['occupation'];
    final isIdVerified = user['id_verified'] == true;
    final isInviting = _invitingUserId == userId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Stack(
          children: [
            GestureDetector(
              onTap: () => _navigateToProfile(userId),
              child: CircleAvatar(
                radius: 28,
                backgroundImage: userImageUrl != null 
                    ? NetworkImage(userImageUrl) 
                    : null,
                child: userImageUrl == null 
                    ? Text(
                        userName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            if (isIdVerified)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          userName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              [
                if (userAge != null) '${userAge}歳',
                if (userPrefecture != null) userPrefecture,
                if (userOccupation != null) userOccupation,
              ].join(' • '),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ],
        ),
        trailing: isInviting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(
                onPressed: () => _showInviteConfirmDialog(userId, userName),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink[400],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('招待'),
              ),
      ),
    );
  }

  void _showInviteConfirmDialog(String userId, String userName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループに招待'),
        content: Text('$userName さんを「${widget.group.name}」に招待しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _inviteUser(userId, userName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink[400],
              foregroundColor: Colors.white,
            ),
            child: const Text('招待する'),
          ),
        ],
      ),
    );
  }

  // 年齢フィルターダイアログ
  void _showAgeFilterDialog() async {
    int? tempMinAge = _minAge;
    int? tempMaxAge = _maxAge;

    final result = await showDialog<Map<String, int?>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('年齢を選択'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('最小年齢: '),
                      Expanded(
                        child: DropdownButton<int?>(
                          value: tempMinAge,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('指定なし'),
                            ),
                            ...List.generate(63, (index) => index + 18)
                                .map((age) => DropdownMenuItem<int?>(
                                      value: age,
                                      child: Text('${age}歳'),
                                    )),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              tempMinAge = value;
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
                        child: DropdownButton<int?>(
                          value: tempMaxAge,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('指定なし'),
                            ),
                            ...List.generate(63, (index) => index + 18)
                                .map((age) => DropdownMenuItem<int?>(
                                      value: age,
                                      child: Text('${age}歳'),
                                    )),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              tempMaxAge = value;
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'minAge': tempMinAge,
                      'maxAge': tempMaxAge,
                    });
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _minAge = result['minAge'];
        _maxAge = result['maxAge'];
      });
      _searchUsers();
    }
  }

  // 性別フィルターダイアログ
  void _showGenderFilterDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempSelection),
                  child: const Text('OK'),
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
  }

  // 職業フィルターダイアログ
  void _showOccupationFilterDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        List<String> tempSelection = List.from(_selectedOccupations);
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempSelection),
                  child: const Text('OK'),
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
  }

  // カテゴリーフィルターダイアログ
  void _showCategoryFilterDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        List<String> tempSelection = List.from(_selectedFavoriteCategories);
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempSelection),
                  child: const Text('OK'),
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
  }

  void _navigateToProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileViewPage(userId: userId),
      ),
    );
  }

  // ハッシュタグフィルターダイアログ
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
} 