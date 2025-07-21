import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../services/user_image_service.dart';
import '../services/web_image_helper.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// import 'dart:typed_data';
// import 'dart:ui' as ui;

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  
  // フォームデータ
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  String? _selectedGender;
  DateTime? _birthDate;
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedDay;
  String? _selectedPrefecture;
  String? _selectedOccupation;
  bool _weekendOff = false;
  List<String> _selectedCategories = [];
  String? _currentImageUrl;
  dynamic _selectedImage; // Web: XFile, モバイル: File
  
  // 学校関連の設定
  String? _selectedSchoolId;
  String? _selectedSchoolName;
  String? _selectedSchoolType;
  bool _showSchool = true;
  
  // 学校検索関連
  List<Map<String, dynamic>> _schoolSearchResults = [];
  bool _isSearchingSchools = false;
  final TextEditingController _schoolSearchController = TextEditingController();
  
  // プライバシー設定
  bool _hideFromSameSchool = false;
  bool _visibleOnlyIfLiked = false;
  
  // 複数画像管理
  List<Map<String, dynamic>> _userImages = [];
  bool _isLoadingImages = false;
  
  // タグ・MBTI選択用
  List<String> _selectedTags = [];
  String? _selectedMbti;
  
  // ハッシュタグ折り畳み状態
  bool _isRestaurantTagsExpanded = false;
  bool _isHobbyTagsExpanded = false;
  bool _isPersonalityTagsExpanded = false;

  // マッチしたい人の特徴
  String? _selectedPreferredAgeRange;
  String? _selectedPaymentPreference;
  String? _selectedPreferredGender;

  // ハッシュタグリスト
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
  static const List<String> _mbtiTypes = [
    'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
    'ISTP', 'ISFP', 'INFP', 'INTP',
    'ESTP', 'ESFP', 'ENFP', 'ENTP',
    'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ',
  ];

  // 選択肢
  static const List<String> _genders = ['男性', '女性', 'その他'];
  static const List<String> _prefectures = [
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
    '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
    '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県',
    '三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県',
    '鳥取県', '島根県', '岡山県', '広島県', '山口県',
    '徳島県', '香川県', '愛媛県', '高知県',
    '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
  ];
  static const List<String> _occupations = [
    '会社員', 'エンジニア', '医療従事者', '教育関係', '公務員', 
    'フリーランス', '学生', 'その他'
  ];
  
  // 学校種別の選択肢
  static const List<String> _schoolTypes = [
    'university', 'graduate_school', 'vocational_school', 'college'
  ];
  static const List<String> _schoolTypeLabels = [
    '大学', '大学院', '専門学校', '短大'
  ];
  static const List<String> _categories = [
    '居酒屋', 'カラオケ・パーティ', 'バー・カクテル', 'ラーメン', '和食', '韓国料理',
    'カフェ・スイーツ', '焼肉・ホルモン', 'アジア・エスニック料理', '洋食', '中華',
    'ダイニングバー・バル', 'イタリアン・フレンチ', 'その他グルメ', 'お好み焼き・もんじゃ',
    '各国料理', '創作料理',
  ];

  // マッチング設定の選択肢
  static const List<String> _ageRanges = [
    '18-25', '26-35', '36-45', '46-55', '56+'
  ];
  static const List<String> _paymentPreferences = [
    'split', 'pay', 'be_paid'
  ];
  static const List<String> _paymentPreferenceLabels = [
    '割り勘希望', '奢りたい', '奢られたい'
  ];
  static const List<String> _preferredGenders = [
    '男性', '女性', 'どちらでも'
  ];

  // 年の選択肢を生成（現在年-100から現在年まで）
  List<int> _generateYears() {
    final currentYear = DateTime.now().year;
    return List.generate(100, (index) => currentYear - index);
  }

  // 月の選択肢を生成
  List<int> _generateMonths() {
    return List.generate(12, (index) => index + 1);
  }

  // 日の選択肢を生成（選択された年月に応じて）
  List<int> _generateDays() {
    if (_selectedYear == null || _selectedMonth == null) {
      return List.generate(31, (index) => index + 1);
    }
    
    final currentDate = DateTime.now();
    final selectedDate = DateTime(_selectedYear!, _selectedMonth!);
    
    // 選択された年月が現在の年月の場合、現在の日付以降は選択不可
    if (_selectedYear == currentDate.year && _selectedMonth == currentDate.month) {
      return List.generate(currentDate.day, (index) => index + 1);
    }
    
    // その月の最大日数を取得
    final daysInMonth = DateTime(_selectedYear!, _selectedMonth! + 1, 0).day;
    return List.generate(daysInMonth, (index) => index + 1);
  }

  // 生年月日の更新
  void _updateBirthDate() {
    if (_selectedYear != null && _selectedMonth != null && _selectedDay != null) {
      _birthDate = DateTime(_selectedYear!, _selectedMonth!, _selectedDay!);
    }
  }

  // 18歳以上かチェック
  bool _isOver18() {
    if (_birthDate == null) return false;
    
    final now = DateTime.now();
    final age = now.year - _birthDate!.year;
    
    // 誕生日がまだ来ていない場合は1歳引く
    if (now.month < _birthDate!.month || 
        (now.month == _birthDate!.month && now.day < _birthDate!.day)) {
      return (age - 1) >= 18;
    }
    
    return age >= 18;
  }

  String _getPaymentPreferenceLabel(String? preference) {
    if (preference == null || preference.isEmpty) {
      return '未設定';
    }
    switch (preference) {
      case 'split':
        return '割り勘希望';
      case 'pay':
        return '奢りたい';
      case 'be_paid':
        return '奢られたい';
      default:
        return '未設定';
    }
  }

  String _getSchoolTypeLabel(String? schoolType) {
    if (schoolType == null || schoolType.isEmpty) {
      return '未設定';
    }
    final index = _schoolTypes.indexOf(schoolType);
    if (index != -1) {
      return _schoolTypeLabels[index];
    }
    return '未設定';
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadUserImages();
  }

  /// 🔄 HEIC画像をJPEGに変換（identity_verification_service.dartと同様）
  Future<File?> _convertHeicToJpeg(File heicFile) async {
    try {

      // HEICファイルを読み込み
      final bytes = await heicFile.readAsBytes();
      
      // imageパッケージでデコード（HEIC対応）
      final image = img.decodeImage(bytes);
      if (image == null) {
        return null;
      }
      

      // JPEGエンコード（品質90%）
      final jpegBytes = img.encodeJpg(image, quality: 90);
      
      // 一時ディレクトリに保存
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jpegFile = File('${tempDir.path}/converted_heic_$timestamp.jpg');
      
      await jpegFile.writeAsBytes(jpegBytes);
      
      
      return jpegFile;
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _schoolSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getUserProfile');
      
      final result = await callable.call();
      
      if (result.data != null && result.data['exists'] == true) {
        final userData = result.data['user'];
        
        // 型変換を安全に行う
        final userDataMap = userData is Map ? Map<String, dynamic>.from(userData) : userData;
        
        setState(() {
          _nameController.text = userDataMap['name']?.toString() ?? '';
          _bioController.text = userDataMap['bio']?.toString() ?? '';
          _selectedGender = userDataMap['gender']?.toString();
          _selectedPrefecture = userDataMap['prefecture']?.toString();
          _selectedOccupation = userDataMap['occupation']?.toString();
          _weekendOff = userDataMap['weekend_off'] == true;
          
          // favorite_categoriesの安全な変換
          final categories = userDataMap['favorite_categories'];
          if (categories is List) {
            _selectedCategories = categories.map((e) => e.toString()).toList();
          } else {
            _selectedCategories = [];
          }
          
          // ハッシュタグの読み込み
          final tags = userDataMap['tags'];
          if (tags is List) {
            _selectedTags = tags.map((e) => e.toString()).toList();
          } else {
            _selectedTags = [];
          }
          
          // MBTIの読み込み
          _selectedMbti = userDataMap['mbti']?.toString();
          
          // マッチしたい人の特徴の読み込み
          _selectedPreferredAgeRange = userDataMap['preferred_age_range']?.toString();
          _selectedPaymentPreference = userDataMap['payment_preference']?.toString();
          _selectedPreferredGender = userDataMap['preferred_gender']?.toString();
          
          // 学校関連の読み込み
          _selectedSchoolId = userDataMap['school_id']?.toString();
          _selectedSchoolName = userDataMap['school_name']?.toString();
          _selectedSchoolType = userDataMap['school_type']?.toString();
          _showSchool = userDataMap['show_school'] ?? true;
          
          // 既存の学校名がある場合、検索テキストフィールドに表示
          if (_selectedSchoolName != null && _selectedSchoolName!.isNotEmpty) {
            _schoolSearchController.text = _selectedSchoolName!;
          }
          
          // プライバシー設定の読み込み
          _hideFromSameSchool = userDataMap['hide_from_same_school'] ?? false;
          _visibleOnlyIfLiked = userDataMap['visible_only_if_liked'] ?? false;
          
          _currentImageUrl = userDataMap['image_url']?.toString();
          
          // 生年月日の処理
          if (userDataMap['birth_date'] != null) {
            try {
              final birthDateData = userDataMap['birth_date'];
              
              // 文字列の場合
              if (birthDateData is String) {
                _birthDate = DateTime.parse(birthDateData);
              }
              // Mapオブジェクトの場合（Firestoreのタイムスタンプなど）
              else if (birthDateData is Map) {
                // 空のMapの場合はスキップ
                if (birthDateData.isEmpty) {
                } else if (birthDateData.containsKey('_seconds')) {
                  // Firestoreタイムスタンプ形式
                  final seconds = birthDateData['_seconds'];
                  _birthDate = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
                } else if (birthDateData.containsKey('seconds')) {
                  // 別のタイムスタンプ形式
                  final seconds = birthDateData['seconds'];
                  _birthDate = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
                } else {
                }
              }
              // その他の形式
              else {
              }
              
              // 生年月日が設定された場合、個別の年月日も設定
              if (_birthDate != null) {
                _selectedYear = _birthDate!.year;
                _selectedMonth = _birthDate!.month;
                _selectedDay = _birthDate!.day;
              }
            } catch (e) {
            }
          }
          
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィール情報の取得に失敗しました')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    }
  }

  Future<void> _pickImage() async {
    // キーボードを閉じる
    FocusScope.of(context).unfocus();
    
    final ImagePicker picker = ImagePicker();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('ギャラリーから選択'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _processImageSelection(picker, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('カメラで撮影'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _processImageSelection(picker, ImageSource.camera);
                  },
                ),
                if (_currentImageUrl != null || _selectedImage != null)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('画像を削除'),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedImage = null;
                        _currentImageUrl = null;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 🖼️ 画像選択とHEIC変換処理（identity_verification_service.dartと同様）
  Future<void> _processImageSelection(ImagePicker picker, ImageSource source) async {
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
        requestFullMetadata: false,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (image != null) {
        if (kIsWeb) {
          // Web: XFileをそのまま保持
          setState(() {
            _selectedImage = image;
          });
        } else {
          // モバイル: Fileに変換
          final File originalFile = File(image.path);
          // ここにHEIC変換等の処理を入れてもOK
          setState(() {
            _selectedImage = originalFile;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画像の選択に失敗しました: $e')),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return _currentImageUrl;
    
    try {
      // Web版での認証状態確認を強化
      if (kIsWeb) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('Web版: 認証状態が確認できません。再ログインしてください。');
        }
        
        // 認証トークンを明示的に取得して確認
        try {
          final token = await user.getIdToken(true);
          if (token == null || token.isEmpty) {
            throw Exception('Web版: 認証トークンが無効です。再ログインしてください。');
          }
        } catch (e) {
          throw Exception('Web版: 認証状態が無効です。再ログインしてください。');
        }
      }

      String imageUrl;
      
      if (kIsWeb) {
        // Web版: XFileをUint8Listでアップロード
        if (_selectedImage is XFile) {
          final bytes = await (_selectedImage as XFile).readAsBytes();
          imageUrl = await _uploadImageBytes(bytes, 'profile');
        } else {
          throw Exception('Web環境ではXFileが必要です');
        }
      } else {
        // モバイル版: Fileでアップロード（HEIC変換含む）
        if (_selectedImage is File) {
          final convertedFile = await _convertHeicToJpeg(_selectedImage as File);
          final finalFile = convertedFile ?? _selectedImage as File;
          imageUrl = await _uploadImageFile(finalFile, 'profile');
        } else {
          throw Exception('モバイル環境ではFileが必要です');
        }
      }

      return imageUrl;
    } catch (e) {
      
      String errorMessage = '画像のアップロードに失敗しました';
      if (e.toString().contains('認証状態が確認できません') || 
          e.toString().contains('認証トークンが無効') ||
          e.toString().contains('認証状態が無効') ||
          e.toString().contains('unauthorized')) {
        errorMessage = '認証エラーが発生しました。再ログインしてください。';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  // Web版用: Uint8Listで画像アップロード
  Future<String> _uploadImageBytes(Uint8List bytes, String folder) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('$folder-images')
          .child(user.uid)
          .child(fileName);

      // Web版では明示的に認証トークンを設定
      final token = await user.getIdToken(true);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': user.uid,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );
      
      final uploadTask = storageRef.putData(bytes, metadata);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      rethrow;
    }
  }

  // モバイル版用: Fileで画像アップロード
  Future<String> _uploadImageFile(File file, String folder) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('$folder-images')
          .child(user.uid)
          .child(fileName);

      final uploadTask = storageRef.putFile(file);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    // キーボードを閉じる
    FocusScope.of(context).unfocus();
    
    // 18歳未満チェック
    if (!_isOver18()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('18歳以上である必要があります'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // 画像をアップロード
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
        if (imageUrl == null) {
          throw Exception('画像のアップロードに失敗しました');
        }
      } else {
        imageUrl = _currentImageUrl;
      }
      
      // プロフィールを更新
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('updateUserProfile');
      
      final data = {
        'name': _nameController.text,
        'bio': _bioController.text,
        'gender': _selectedGender,
        'birth_date': _birthDate?.toIso8601String(),
        'prefecture': _selectedPrefecture,
        'occupation': _selectedOccupation,
        'weekend_off': _weekendOff,
        'favorite_categories': _selectedCategories,
        'image_url': imageUrl,
        'tags': _selectedTags,
        'mbti': _selectedMbti,
        'preferred_age_range': _selectedPreferredAgeRange,
        'payment_preference': _selectedPaymentPreference,
        'preferred_gender': _selectedPreferredGender,
        'school_id': _selectedSchoolId,
        'show_school': _showSchool,
        'hide_from_same_school': _hideFromSameSchool,
        'visible_only_if_liked': _visibleOnlyIfLiked,
      };
      
      await callable.call(data);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('プロフィールを更新しました'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.pop(context);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // 複数画像を読み込み
  Future<void> _loadUserImages() async {
    setState(() {
      _isLoadingImages = true;
    });

    try {
      final images = await UserImageService.getUserImages();
      setState(() {
        _userImages = images;
        _isLoadingImages = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingImages = false;
      });
    }
  }

  // 複数画像を追加
  Future<void> _addMultipleImage() async {
    // キーボードを閉じる
    FocusScope.of(context).unfocus();
    
    // キーボードが完全に閉じるまで少し待つ
    await Future.delayed(const Duration(milliseconds: 100));
    
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('ギャラリーから選択'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickAndUploadMultipleImage(picker, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('カメラで撮影'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickAndUploadMultipleImage(picker, ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadMultipleImage(ImagePicker picker, ImageSource source) async {
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
        requestFullMetadata: false,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (image != null) {
        // ローディング表示
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        try {
          dynamic finalImage;
          
                  if (kIsWeb) {
          // Web: XFileをそのまま使用
          finalImage = image;
        } else {
            // モバイル: Fileに変換
            final File originalFile = File(image.path);
            
            // ファイル拡張子をチェック
            final String extension = image.path.toLowerCase();
            final bool isHeic = extension.endsWith('.heic') || extension.endsWith('.heif');
            final bool isFromImagePicker = image.path.contains('image_picker_');
            
            if (isHeic) {
              final convertedFile = await _convertHeicToJpeg(originalFile);
              finalImage = convertedFile ?? originalFile;
            } else if (isFromImagePicker) {
              final convertedFile = await _convertHeicToJpeg(originalFile);
              finalImage = convertedFile ?? originalFile;
            } else {
              finalImage = originalFile;
            }
          }

          final result = await UserImageService.uploadImage(
            finalImage,
            displayOrder: _userImages.length + 1,
          );

          Navigator.pop(context); // ローディングダイアログを閉じる

          if (result != null) {
            // 画像リストを再読み込み
            await _loadUserImages();
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('画像をアップロードしました'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            throw Exception('画像のアップロードに失敗しました');
          }
        } catch (e) {
          Navigator.pop(context); // ローディングダイアログを閉じる
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('アップロードに失敗しました: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('画像の選択に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('プロフィール編集'),
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール編集'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // プロフィール画像
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[300],
                        ),
                        child: ClipOval(
                          child: _selectedImage != null
                              ? (kIsWeb
                                  ? Image.network(
                                      (_selectedImage as XFile).path,
                                      fit: BoxFit.cover,
                                      width: 120,
                                      height: 120,
                                    )
                                  : Image.file(
                                      _selectedImage as File,
                                      fit: BoxFit.cover,
                                      width: 120,
                                      height: 120,
                                    ))
                              : _currentImageUrl != null
                                  ? (kIsWeb
                                      ? WebImageHelper.buildProfileImage(
                                          _currentImageUrl!,
                                          size: 120,
                                          isCircular: false, // 既にClipOvalで囲まれているため
                                        )
                                      : Image.network(
                                          _currentImageUrl!,
                                          fit: BoxFit.cover,
                                          width: 120,
                                          height: 120,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.person,
                                              size: 40,
                                              color: Colors.grey,
                                            );
                                          },
                                        ))
                                  : const Icon(
                                      Icons.add_a_photo,
                                      size: 40,
                                      color: Colors.grey,
                                    ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.edit),
                      label: const Text('画像を変更'),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 複数画像セクション
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '追加の写真',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '${_userImages.length}/10',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '最大10枚まで追加できます',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMultipleImagesGrid(),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // 名前
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名前',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '名前を入力してください';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 自己紹介文
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: '自己紹介文',
                  border: OutlineInputBorder(),
                  hintText: 'あなたについて教えてください...',
                ),
                maxLines: 5,
                minLines: 3,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                validator: (value) {
                  if (value != null && value.length > 500) {
                    return '自己紹介文は500文字以内で入力してください';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 性別
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(
                  labelText: '性別',
                  border: OutlineInputBorder(),
                ),
                items: _genders.map((gender) {
                  return DropdownMenuItem(
                    value: gender,
                    child: Text(gender),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 生年月日
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '生年月日',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 年
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: const InputDecoration(
                            labelText: '年',
                            border: OutlineInputBorder(),
                          ),
                          items: _generateYears().map((year) {
                            return DropdownMenuItem(
                              value: year,
                              child: Text('${year}年'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedYear = value;
                              // 年が変更されたら日をリセット（月末日が変わる可能性があるため）
                              if (_selectedMonth != null && _selectedDay != null) {
                                final daysInMonth = _generateDays();
                                if (!daysInMonth.contains(_selectedDay)) {
                                  _selectedDay = null;
                                }
                              }
                              _updateBirthDate();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 月
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedMonth,
                          decoration: const InputDecoration(
                            labelText: '月',
                            border: OutlineInputBorder(),
                          ),
                          items: _generateMonths().map((month) {
                            return DropdownMenuItem(
                              value: month,
                              child: Text('${month}月'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedMonth = value;
                              // 月が変更されたら日をリセット（月末日が変わる可能性があるため）
                              if (_selectedDay != null) {
                                final daysInMonth = _generateDays();
                                if (!daysInMonth.contains(_selectedDay)) {
                                  _selectedDay = null;
                                }
                              }
                              _updateBirthDate();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 日
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedDay,
                          decoration: const InputDecoration(
                            labelText: '日',
                            border: OutlineInputBorder(),
                          ),
                          items: _generateDays().map((day) {
                            return DropdownMenuItem(
                              value: day,
                              child: Text('${day}日'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedDay = value;
                              _updateBirthDate();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // 都道府県
              DropdownButtonFormField<String>(
                value: _selectedPrefecture,
                decoration: const InputDecoration(
                  labelText: '都道府県',
                  border: OutlineInputBorder(),
                ),
                items: _prefectures.map((prefecture) {
                  return DropdownMenuItem(
                    value: prefecture,
                    child: Text(prefecture),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPrefecture = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 職業
              DropdownButtonFormField<String>(
                value: _selectedOccupation,
                decoration: const InputDecoration(
                  labelText: '職業',
                  border: OutlineInputBorder(),
                ),
                items: _occupations.map((occupation) {
                  return DropdownMenuItem(
                    value: occupation,
                    child: Text(occupation),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedOccupation = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 土日休み
              SwitchListTile(
                title: const Text('土日休み'),
                value: _weekendOff,
                onChanged: (value) {
                  setState(() {
                    _weekendOff = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 好きなカテゴリ
              const Text(
                '好きなカテゴリ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((category) {
                  final isSelected = _selectedCategories.contains(category);
                  return FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategories.add(category);
                        } else {
                          _selectedCategories.remove(category);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('ハッシュタグ（複数選択可）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedTags.length}個選択中',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // レストラン・ご飯系タグ（折り畳み）
              ExpansionTile(
                title: Text(
                  'レストラン・ご飯系（${_restaurantTags.where((tag) => _selectedTags.contains(tag)).length}個選択）',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                leading: Icon(
                  Icons.restaurant,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
                initiallyExpanded: _isRestaurantTagsExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _isRestaurantTagsExpanded = expanded;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _restaurantTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 13)),
                          selected: isSelected,
                          selectedColor: Colors.blue.shade100,
                          checkmarkColor: Colors.blue.shade700,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              
              // 趣味系タグ（折り畳み）
              ExpansionTile(
                title: Text(
                  '趣味系（${_hobbyTags.where((tag) => _selectedTags.contains(tag)).length}個選択）',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                leading: Icon(
                  Icons.sports_esports,
                  color: Colors.green.shade600,
                  size: 20,
                ),
                initiallyExpanded: _isHobbyTagsExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _isHobbyTagsExpanded = expanded;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _hobbyTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 13)),
                          selected: isSelected,
                          selectedColor: Colors.green.shade100,
                          checkmarkColor: Colors.green.shade700,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              
              // 性格系タグ（折り畳み）
              ExpansionTile(
                title: Text(
                  '性格系（${_personalityTags.where((tag) => _selectedTags.contains(tag)).length}個選択）',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                leading: Icon(
                  Icons.psychology,
                  color: Colors.purple.shade600,
                  size: 20,
                ),
                initiallyExpanded: _isPersonalityTagsExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _isPersonalityTagsExpanded = expanded;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _personalityTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 13)),
                          selected: isSelected,
                          selectedColor: Colors.purple.shade100,
                          checkmarkColor: Colors.purple.shade700,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('MBTI（1つ選択）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_selectedMbti != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _selectedMbti!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'MBTIは性格タイプを表す指標です。最も当てはまるものを1つ選択してください。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedMbti,
                decoration: const InputDecoration(
                  labelText: 'MBTIタイプ',
                  border: OutlineInputBorder(),
                  hintText: 'MBTIタイプを選択してください',
                ),
                items: _mbtiTypes.map((mbti) {
                  return DropdownMenuItem(
                    value: mbti,
                    child: Text(mbti),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedMbti = value;
                  });
                },
              ),
              
              const SizedBox(height: 32),
              
              // 学校設定セクション
              const Text(
                '学校設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '大学・専門学校などの情報を設定できます（任意）',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              
              // 学校検索&選択
              const Text(
                '学校名',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  TextField(
                    controller: _schoolSearchController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.school),
                      hintText: '学校名を入力して検索',
                      suffixIcon: _selectedSchoolId != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSchoolSelection,
                          )
                        : _isSearchingSchools
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                    ),
                    onChanged: _searchSchools,
                  ),
                  
                  // 検索結果表示
                  if (_schoolSearchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
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
                            onTap: () => _selectSchool(school),
                          );
                        },
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // 学校種別選択
              DropdownButtonFormField<String?>(
                value: _selectedSchoolType,
                decoration: const InputDecoration(
                  labelText: '学校種別',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                hint: const Text('学校の種別を選択'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('未設定'),
                  ),
                  ..._schoolTypes.map((type) {
                    return DropdownMenuItem<String?>(
                      value: type,
                      child: Text(_schoolTypeLabels[_schoolTypes.indexOf(type)]),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedSchoolType = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 学校名表示設定
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.visibility, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text(
                            '学校名の表示設定',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('プロフィールに学校名を表示する'),
                        subtitle: const Text('オフにすると他のユーザーには学校名が表示されません'),
                        value: _showSchool,
                        onChanged: (value) {
                          setState(() {
                            _showSchool = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // プライバシー設定セクション
              const Text(
                'プライバシー設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'あなたのプロフィールの表示を制御します',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 身内バレ防止機能
                      SwitchListTile(
                        title: const Text('身内バレ防止'),
                        subtitle: const Text('同じ学校の人からあなたのプロフィールが見えなくなります'),
                        value: _hideFromSameSchool,
                        secondary: Icon(Icons.school, color: Colors.orange),
                        onChanged: (value) {
                          setState(() {
                            _hideFromSameSchool = value;
                          });
                        },
                      ),
                      const Divider(),
                      // いいね限定表示機能
                      SwitchListTile(
                        title: const Text('いいね限定表示'),
                        subtitle: const Text('あなたがいいねした人にのみプロフィールが表示されます'),
                        value: _visibleOnlyIfLiked,
                        secondary: Icon(Icons.favorite, color: Colors.pink),
                        onChanged: (value) {
                          setState(() {
                            _visibleOnlyIfLiked = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // マッチしたい人の特徴セクション
              const Text(
                'マッチしたい人の特徴',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'あなたのマッチング設定を選択してください',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              
              // 年齢範囲選択
              DropdownButtonFormField<String?>(
                value: _selectedPreferredAgeRange,
                decoration: const InputDecoration(
                  labelText: '希望年齢範囲',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cake),
                ),
                hint: const Text('年齢範囲を選択'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('未設定'),
                  ),
                  ..._ageRanges.map((range) {
                    return DropdownMenuItem<String?>(
                      value: range,
                      child: Text('${range}歳'),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedPreferredAgeRange = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 支払い方法選択
              DropdownButtonFormField<String?>(
                value: _selectedPaymentPreference,
                decoration: const InputDecoration(
                  labelText: '支払い方法',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                hint: const Text('支払い方法を選択'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('未設定'),
                  ),
                  ..._paymentPreferences.map((pref) {
                    return DropdownMenuItem<String?>(
                      value: pref,
                      child: Text(_paymentPreferenceLabels[
                          _paymentPreferences.indexOf(pref)]),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedPaymentPreference = value;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // 希望性別選択
              DropdownButtonFormField<String?>(
                value: _selectedPreferredGender,
                decoration: const InputDecoration(
                  labelText: '希望性別',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.favorite),
                ),
                hint: const Text('希望性別を選択'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('未設定'),
                  ),
                  ..._preferredGenders.map((gender) {
                    return DropdownMenuItem<String?>(
                      value: gender,
                      child: Text(gender),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedPreferredGender = value;
                  });
                },
              ),
              
              const SizedBox(height: 32),
              
              // 共有機能セクション
              _buildShareSection(),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultipleImagesGrid() {
    if (_isLoadingImages) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // 最大10枚まで表示（9枚の画像 + 1枚の追加ボタン）
    final displayImages = _userImages.take(9).toList();
    final canAddMore = _userImages.length < 10;
    
    // 動的に高さを計算（3:2の比率）- profile_view_page.dartと同じ計算方法
    final screenWidth = MediaQuery.of(context).size.width;
    final cardPadding = 32.0; // 外側のpadding
    final availableWidth = screenWidth - cardPadding; // 外側のpadding
    final cellWidth = (availableWidth - 8) / 3; // 3列、間隔8px
    final cellHeight = cellWidth * 2 / 3; // 3:2の比率
    final totalHeight = cellHeight * 3 + 8; // 3行分の高さ + 間隔
    
    return Container(
      height: totalHeight, // 動的に計算された高さ
      child: Column(
        children: [
          // 3列のグリッドレイアウト
          for (int row = 0; row < 3; row++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    for (int col = 0; col < 3; col++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                            right: col < 2 ? 4 : 0,
                          ),
                          child: _buildImageCell(row * 3 + col, displayImages, canAddMore),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageCell(int index, List<Map<String, dynamic>> displayImages, bool canAddMore) {
    // 画像がある場合
    if (index < displayImages.length) {
      final imageData = displayImages[index];
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // 画像表示
              Positioned.fill(
                child: Image.network(
                  imageData['image_url'],
                  fit: BoxFit.cover,
                ),
              ),
              // 編集ボタン
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: () => _editImageMetadata(imageData),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              // 削除ボタン
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deleteImage(imageData['id']),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              // キャプション表示
              if (imageData['caption'] != null && imageData['caption'].toString().isNotEmpty)
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      imageData['caption'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    // 追加ボタン
    if (index == displayImages.length && canAddMore) {
      return GestureDetector(
        onTap: _addMultipleImage,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.grey.shade400,
              style: BorderStyle.solid,
              width: 2,
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate, 
                     size: 32, 
                     color: Colors.grey),
                SizedBox(height: 4),
                Text('写真を追加', 
                     style: TextStyle(
                       fontSize: 10, 
                       color: Colors.grey,
                       fontWeight: FontWeight.w500,
                     )),
              ],
            ),
          ),
        ),
      );
    }
    
    // 空のセル
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  // 画像削除
  Future<void> _deleteImage(String imageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('画像を削除'),
        content: const Text('この画像を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await UserImageService.deleteImage(imageId);
        if (success) {
          await _loadUserImages();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('画像を削除しました'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception('削除に失敗しました');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 画像メタデータ編集ダイアログ
  void _editImageMetadata(Map<String, dynamic> imageData) {
    final TextEditingController captionController = TextEditingController(text: imageData['caption'] ?? '');
    final TextEditingController restaurantSearchController = TextEditingController();
    
    Map<String, dynamic>? selectedRestaurant;
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;
    
    // 既存のレストラン情報があれば表示
    if (imageData['restaurant_id'] != null) {
      selectedRestaurant = {
        'id': imageData['restaurant_id'],
        'name': imageData['restaurant_name'] ?? '選択されたレストラン',
      };
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => GestureDetector(
          onTap: () {
            // キーボードを閉じる
            FocusScope.of(context).unfocus();
          },
          child: AlertDialog(
            title: const Text('投稿を編集'),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // 画像プレビュー
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageData['image_url'],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // キャプション入力
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 120, // 最大高さを制限
                    ),
                    child: TextField(
                      controller: captionController,
                      maxLines: null,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'キャプション',
                        hintText: 'この投稿について説明してください...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      textAlignVertical: TextAlignVertical.top,
                      expands: false,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // レストラン検索
                  TextField(
                    controller: restaurantSearchController,
                    decoration: InputDecoration(
                      labelText: 'レストラン検索',
                      hintText: 'レストラン名を入力してください',
                      border: const OutlineInputBorder(),
                      suffixIcon: isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () async {
                                // キーボードを閉じる
                                FocusScope.of(context).unfocus();
                                
                                final query = restaurantSearchController.text.trim();
                                if (query.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('検索キーワードを入力してください'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }
                                
                                setState(() {
                                  isSearching = true;
                                });
                                
                                try {
                                  final results = await UserImageService.searchRestaurants(query);
                                  setState(() {
                                    searchResults = results;
                                    isSearching = false;
                                  });
                                  
                                  if (results.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('検索結果が見つかりませんでした'),
                                        backgroundColor: Colors.grey,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setState(() {
                                    isSearching = false;
                                    searchResults = [];
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('検索エラー: ${e.toString()}'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                    ),
                    onChanged: (value) async {
                      if (value.isEmpty) {
                        setState(() {
                          searchResults = [];
                          isSearching = false;
                        });
                        return;
                      }
                      
                      setState(() {
                        isSearching = true;
                      });
                      
                      try {
                        final results = await UserImageService.searchRestaurants(value);
                        setState(() {
                          searchResults = results;
                          isSearching = false;
                        });
                      } catch (e) {
                        setState(() {
                          isSearching = false;
                          searchResults = [];
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('検索エラー: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  
                  // 選択されたレストラン表示
                  if (selectedRestaurant != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.restaurant, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedRestaurant!['name'],
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                selectedRestaurant = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  
                  // 検索結果表示
                  if (searchResults.isNotEmpty)
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final restaurant = searchResults[index];
                          return ListTile(
                            leading: const Icon(Icons.restaurant),
                            title: Text(restaurant['name'] ?? '名前未設定'),
                            subtitle: Text(
                              restaurant['address'] ?? 
                              restaurant['prefecture'] ?? 
                              restaurant['category'] ?? 
                              '詳細不明'
                            ),
                            onTap: () {
                              setState(() {
                                selectedRestaurant = {
                                  'id': restaurant['id'] ?? restaurant['restaurant_id'],
                                  'name': restaurant['name'] ?? '名前未設定',
                                  'address': restaurant['address'],
                                  'prefecture': restaurant['prefecture'],
                                  'category': restaurant['category'],
                                };
                                restaurantSearchController.clear();
                                searchResults = [];
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                // メタデータを更新
                
                final success = await UserImageService.updateImageMetadata(
                  imageData['id'],
                  caption: captionController.text.trim().isEmpty ? null : captionController.text.trim(),
                  restaurantId: selectedRestaurant?['id']?.toString(),
                  restaurantName: selectedRestaurant?['name'],
                );
                
                if (success) {
                  Navigator.pop(context);
                  // 画像リストを再読み込み
                  await _loadUserImages();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('投稿を更新しました'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('更新に失敗しました'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
          ),
        ),
      ),
    );
  }

  // 共有機能セクション
  Widget _buildShareSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '共有機能',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'プロフィールや写真をSNSで共有できます',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          
          // Instagram共有ボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _shareToInstagram,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text(
                'Instagramで共有',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF833AB4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 一般的な共有ボタン
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _shareProfile,
              icon: const Icon(Icons.share, color: Colors.grey),
              label: const Text(
                'プロフィールを共有',
                style: TextStyle(color: Colors.grey),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Instagram共有
  Future<void> _shareToInstagram() async {
    try {
      // Instagram認証確認
      // 実装は InstagramAuthService を使用
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Instagram共有機能は開発中です'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('共有に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // プロフィール共有
  Future<void> _shareProfile() async {
    try {
      // プロフィール情報を構築
      final shareText = _buildShareText();
      
      // クリップボードにコピー
      await Clipboard.setData(ClipboardData(text: shareText));
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('プロフィール情報をクリップボードにコピーしました'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('共有に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 共有テキストを構築
  String _buildShareText() {
    final name = _nameController.text.isNotEmpty ? _nameController.text : '名前未設定';
    final bio = _bioController.text.isNotEmpty ? _bioController.text : '自己紹介未設定';
    final prefecture = _selectedPrefecture ?? '地域未設定';
    final occupation = _selectedOccupation ?? '職業未設定';
    final categories = _selectedCategories.isNotEmpty 
        ? _selectedCategories.join(', ') 
        : '好きなカテゴリ未設定';
    
    return '''
$name のプロフィール

自己紹介：
$bio

地域：$prefecture
職業：$occupation
好きなカテゴリ：$categories

#dating_food_app
''';
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

  // 学校選択
  void _selectSchool(Map<String, dynamic> school) {
    setState(() {
      _selectedSchoolId = school['id'];
      _selectedSchoolName = school['school_name'];
      _selectedSchoolType = school['school_type'];
      _schoolSearchController.text = school['display_name'] ?? school['school_name'];
      _schoolSearchResults = [];
    });
  }

  // 学校選択をクリア
  void _clearSchoolSelection() {
    setState(() {
      _selectedSchoolId = null;
      _selectedSchoolName = null;
      _selectedSchoolType = null;
      _schoolSearchController.clear();
      _schoolSearchResults = [];
    });
  }
}  