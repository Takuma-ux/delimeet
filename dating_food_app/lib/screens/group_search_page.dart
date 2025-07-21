import 'package:flutter/material.dart';
import '../models/group_model.dart';
import '../services/group_service.dart';
import 'group_chat_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroupSearchPage extends StatefulWidget {
  const GroupSearchPage({super.key});

  @override
  State<GroupSearchPage> createState() => _GroupSearchPageState();
}

class _GroupSearchPageState extends State<GroupSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final GroupService _groupService = GroupService();
  
  // 参加申請処理中のグループID
  Set<String> _requestingGroups = {};
  
  // フィルター用の変数
  String? _selectedCategory;
  String? _selectedPrefecture;
  String? _selectedNearestStation;
  int? _minMembers;
  int? _maxMembers;
  List<String> _selectedTags = [];
  
  // 選択肢の定数
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
  
  static const List<String> _prefectures = [
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
    '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
    '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県',
    '三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県',
    '鳥取県', '島根県', '岡山県', '広島県', '山口県',
    '徳島県', '香川県', '愛媛県', '高知県',
    '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedCategory = null;
      _selectedPrefecture = null;
      _selectedNearestStation = null;
      _minMembers = null;
      _maxMembers = null;
      _selectedTags.clear();
    });
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_searchController.text.isNotEmpty) count++;
    if (_selectedCategory != null) count++;
    if (_selectedPrefecture != null) count++;
    if (_selectedNearestStation != null) count++;
    if (_minMembers != null) count++;
    if (_maxMembers != null) count++;
    if (_selectedTags.isNotEmpty) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'グループを探す',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.pink[400],
        elevation: 0,
      ),
      body: Column(
        children: [
          // 検索バー
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'グループ名や説明で検索',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                
                // フィルターチップ
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // カテゴリフィルター
                      FilterChip(
                        label: Text(_selectedCategory ?? 'カテゴリ'),
                        selected: _selectedCategory != null,
                        onSelected: (_) => _showCategoryDialog(),
                      ),
                      const SizedBox(width: 8),
                      
                      // 都道府県フィルター
                      FilterChip(
                        label: Text(_selectedPrefecture ?? '都道府県'),
                        selected: _selectedPrefecture != null,
                        onSelected: (_) => _showPrefectureDialog(),
                      ),
                      const SizedBox(width: 8),
                      
                      // 最寄駅フィルター（都道府県が選択されている場合のみ）
                      if (_selectedPrefecture != null && _stationsByPrefecture.containsKey(_selectedPrefecture))
                        FilterChip(
                          label: Text(_selectedNearestStation ?? '最寄駅'),
                          selected: _selectedNearestStation != null,
                          onSelected: (_) => _showStationDialog(),
                        ),
                      if (_selectedPrefecture != null && _stationsByPrefecture.containsKey(_selectedPrefecture))
                        const SizedBox(width: 8),
                      
                      // 人数フィルター
                      FilterChip(
                        label: Text(_buildMemberCountLabel()),
                        selected: _minMembers != null || _maxMembers != null,
                        onSelected: (_) => _showMemberCountDialog(),
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
                      
                      // フィルタークリア
                      if (_getActiveFilterCount() > 0)
                        ActionChip(
                          label: const Text('クリア'),
                          onPressed: _clearFilters,
                          backgroundColor: Colors.grey[200],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 検索結果
          Expanded(
            child: StreamBuilder<List<Group>>(
              stream: _groupService.searchGroups(
                keyword: _searchController.text.isNotEmpty ? _searchController.text : null,
                category: _selectedCategory,
                prefecture: _selectedPrefecture,
                nearestStation: _selectedNearestStation,
                minMembers: _minMembers,
                maxMembers: _maxMembers,
                tags: _selectedTags.isNotEmpty ? _selectedTags : null,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.pink),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.grey[400],
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'エラーが発生しました',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                final groups = snapshot.data ?? [];

                if (groups.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_outlined,
                          color: Colors.grey[400],
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'グループが見つかりませんでした',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '検索条件を変更してみてください',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    return _buildGroupCard(groups[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(Group group) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isAlreadyMember = currentUserId != null && group.members.contains(currentUserId);
    final isFull = group.members.length >= group.maxMembers;
    final isRequesting = _requestingGroups.contains(group.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // グループ画像
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[300],
                  ),
                  child: group.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.network(
                            group.imageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[300],
                                ),
                                child: const Icon(Icons.group, size: 28, color: Colors.grey),
                              );
                            },
                          ),
                        )
                      : const Icon(Icons.group, size: 28, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                
                // グループ情報
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (group.isPrivate)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'プライベート',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isFull)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '満員',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isAlreadyMember)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '参加済み',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (group.description.isNotEmpty)
                        Text(
                          group.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.people, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '${group.members.length}/${group.maxMembers}人',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (group.category != null) ...[
                            const SizedBox(width: 16),
                            Icon(Icons.restaurant_menu, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                group.category!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (group.prefecture != null) ...[
                            const SizedBox(width: 16),
                            Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                group.prefecture!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // ハッシュタグ表示
                      if (group.tags != null && group.tags!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: group.tags!.take(5).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.pink.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.pink.shade200),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: Colors.pink.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // アクションボタン
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // 参加の有無に関わらず、メンバー確認画面（グループチャット画面）に遷移
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupChatPage(group: group),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey[400]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('メンバー確認'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: isAlreadyMember
                      ? ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupChatPage(group: group),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[400],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('チャット'),
                        )
                      : ElevatedButton(
                          onPressed: isFull || isRequesting
                              ? null
                              : () => _requestJoinGroup(group),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFull ? Colors.grey[400] : Colors.orange[400],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: isRequesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(isFull ? '満員' : '参加申請'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestJoinGroup(Group group) async {
    // 申請メッセージのダイアログを表示
    final message = await _showJoinRequestDialog(group.name);
    if (message == null) return; // キャンセルされた場合

    try {
      setState(() {
        _requestingGroups.add(group.id);
      });

      await _groupService.requestToJoinGroup(group.id, message: message.isNotEmpty ? message : null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「${group.name}」に参加申請を送信しました！'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '参加申請の送信に失敗しました';
        
        if (e.toString().contains('既にグループのメンバーです')) {
          errorMessage = '既にグループに参加済みです';
        } else if (e.toString().contains('既に参加申請を送信済みです')) {
          errorMessage = '既に参加申請を送信済みです';
        } else if (e.toString().contains('グループが見つかりません')) {
          errorMessage = 'グループが見つかりません';
        } else if (e.toString().contains('認証されていません')) {
          errorMessage = 'ログインが必要です';
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
      if (mounted) {
        setState(() {
          _requestingGroups.remove(group.id);
        });
      }
    }
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
    }
  }

  // 参加申請メッセージ入力ダイアログ
  Future<String?> _showJoinRequestDialog(String groupName) async {
    final TextEditingController messageController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('「$groupName」に参加申請'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'グループ管理者に送信するメッセージを入力してください（任意）',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: '例：こんにちは！一緒に美味しいお店を巡りたいです。よろしくお願いします。',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, messageController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[400],
                foregroundColor: Colors.white,
              ),
              child: const Text('申請送信'),
            ),
          ],
        );
      },
    );
  }

  String _buildMemberCountLabel() {
    if (_minMembers != null && _maxMembers != null) {
      return '${_minMembers}〜${_maxMembers}人';
    } else if (_minMembers != null) {
      return '${_minMembers}人以上';
    } else if (_maxMembers != null) {
      return '${_maxMembers}人以下';
    } else {
      return '人数';
    }
  }

  void _showCategoryDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('カテゴリを選択'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('すべて'),
          ),
          ..._categories.map((category) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, category),
              child: Text(category),
            );
          }),
        ],
      ),
    );

    if (result != null || result == null) {
      setState(() {
        _selectedCategory = result;
      });
    }
  }

  void _showPrefectureDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('都道府県を選択'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('すべて'),
          ),
          ..._prefectures.map((prefecture) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, prefecture),
              child: Text(prefecture),
            );
          }),
        ],
      ),
    );

    if (result != null || result == null) {
      setState(() {
        _selectedPrefecture = result;
        // 都道府県が変更されたら最寄駅をリセット
        if (_selectedPrefecture != result) {
          _selectedNearestStation = null;
        }
      });
    }
  }

  void _showStationDialog() async {
    if (_selectedPrefecture == null || !_stationsByPrefecture.containsKey(_selectedPrefecture)) {
      return;
    }

    final stations = _stationsByPrefecture[_selectedPrefecture]!;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('最寄駅を選択'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('すべて'),
          ),
          ...stations.map((station) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, station),
              child: Text(station),
            );
          }),
        ],
      ),
    );

    if (result != null || result == null) {
      setState(() {
        _selectedNearestStation = result;
      });
    }
  }

  void _showMemberCountDialog() async {
    int? tempMinMembers = _minMembers;
    int? tempMaxMembers = _maxMembers;

    final result = await showDialog<Map<String, int?>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('人数を設定'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('最小人数: '),
                      Expanded(
                        child: DropdownButton<int?>(
                          value: tempMinMembers,
                          hint: const Text('選択なし'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('選択なし'),
                            ),
                            ...List.generate(20, (i) => i + 1).map((value) {
                              return DropdownMenuItem<int?>(
                                value: value,
                                child: Text('${value}人'),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              tempMinMembers = value;
                              if (tempMaxMembers != null && value != null && value > tempMaxMembers!) {
                                tempMaxMembers = value;
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
                      const Text('最大人数: '),
                      Expanded(
                        child: DropdownButton<int?>(
                          value: tempMaxMembers,
                          hint: const Text('選択なし'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('選択なし'),
                            ),
                            ...List.generate(100, (i) => i + 1).map((value) {
                              return DropdownMenuItem<int?>(
                                value: value,
                                child: Text('${value}人'),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              tempMaxMembers = value;
                              if (tempMinMembers != null && value != null && value < tempMinMembers!) {
                                tempMinMembers = value;
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'min': tempMinMembers,
                      'max': tempMaxMembers,
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
        _minMembers = result['min'];
        _maxMembers = result['max'];
      });
    }
  }
} 