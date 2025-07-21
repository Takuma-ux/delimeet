import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../services/group_service.dart';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final GroupService _groupService = GroupService();
  
  dynamic _selectedImage; // Web: Uint8List, モバイル: File
  String? _imageUrl;
  bool _isPrivate = false;
  int _maxMembers = 50;
  bool _isCreating = false;
  
  // グループ検索用フィールド
  String? _selectedCategory;
  String? _selectedPrefecture;
  String? _selectedNearestStation;
  
  // ハッシュタグ選択用フィールド
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
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// HEIC画像をJPEGに変換
  Future<File?> _convertHeicToJpeg(File heicFile) async {
    try {

      // HEICファイルを読み込み
      final bytes = await heicFile.readAsBytes();
      
      // imageパッケージでデコード
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

  Future<void> _pickImage() async {
    try {
      final source = await _showImageSourceDialog();
      if (source == null) return;
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _selectedImage = bytes; // Uint8List
          });
        } else {
          File imageFile = File(pickedFile.path);
          final convertedFile = await _convertHeicToJpeg(imageFile);
          setState(() {
            _selectedImage = convertedFile ?? imageFile; // File
          });
        }
      }
    } catch (e) {
      String errorMessage = '画像の選択に失敗しました';
      if (e.toString().contains('認証状態が確認できません')) {
        errorMessage = '認証状態が確認できません。再ログインしてください。';
      } else if (e.toString().contains('unauthorized')) {
        errorMessage = '認証エラーが発生しました。再ログインしてください。';
      }
      _showErrorDialog('$errorMessage: $e');
    }
  }

  // 画像選択方法を選択するダイアログ
  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('画像を選択'),
        content: const Text('画像の取得方法を選択してください'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          // Web版ではカメラボタンを非表示
          if (!kIsWeb)
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('カメラで撮影'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('ギャラリーから選択'),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
    });

    try {
      String? imageUrl;
      
      // 画像をアップロード（選択されている場合）
      if (_selectedImage != null) {
        
        // プロフィール編集画面と同じ方式でアップロード
        imageUrl = await _uploadGroupImage();
        if (imageUrl == null) {
          throw Exception('画像のアップロードに失敗しました');
        }
      } else {
      }

      // グループを作成
      final groupId = await _groupService.createGroup(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
        isPrivate: _isPrivate,
        maxMembers: _maxMembers,
        category: _selectedCategory,
        prefecture: _selectedPrefecture,
        nearestStation: _selectedNearestStation,
        tags: _selectedTags.isNotEmpty ? _selectedTags : null,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('グループを作成しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'グループの作成に失敗しました';
        
        if (e.toString().contains('身分証明書認証が必要です')) {
          errorMessage = 'グループの作成・管理には身分証明書認証が必要です。\n設定画面から身分証明書認証を完了してください。';
        } else if (e.toString().contains('認証されていません')) {
          errorMessage = 'ログインが必要です';
        } else {
          errorMessage = 'エラーが発生しました: ${e.toString().replaceAll('Exception: ', '')}';
        }
        
        _showErrorDialog(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  // グループ画像アップロード（Web/モバイル両対応）
  Future<String?> _uploadGroupImage() async {
    if (_selectedImage == null) return null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーが認証されていません');
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance.ref().child('group-images').child(fileName);
      if (kIsWeb && _selectedImage is Uint8List) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('Web版: 認証状態が確認できません。再ログインしてください。');
        }
        // 認証トークンを明示的に取得して確認
        final token = await user.getIdToken(true);
        if (token == null || token.isEmpty) {
          throw Exception('Web版: 認証トークンが無効です。再ログインしてください。');
        }
        final uploadTask = storageRef.putData(_selectedImage, SettableMetadata(contentType: 'image/jpeg'));
        final snapshot = await uploadTask;
        return await snapshot.ref.getDownloadURL();
      } else if (_selectedImage is File) {
        final uploadTask = storageRef.putFile(_selectedImage);
        final snapshot = await uploadTask;
        return await snapshot.ref.getDownloadURL();
      } else {
        throw Exception('画像データが不正です');
      }
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ハッシュタグ選択ダイアログ
  Future<void> _showHashtagSelectionDialog() async {
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

  /// 画像表示（HEIC変換済みかどうかを判定）
  Widget _buildImageWithColorCorrection(File imageFile) {
    final String fileName = imageFile.path.toLowerCase();
    final bool isConvertedHeic = fileName.contains('converted_heic_') && fileName.endsWith('.jpg');
    final bool isOriginalHeic = fileName.endsWith('.heic') || fileName.endsWith('.heif');
    
    if (isConvertedHeic) {
      // 変換済みHEIC画像（JPEG形式）の場合は成功表示
      return Stack(
        children: [
          // 通常表示
          Positioned.fill(
            child: Image.file(
              imageFile,
              fit: BoxFit.cover,
            ),
          ),
          // 変換成功バッジ
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'HEIC→JPEG',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (isOriginalHeic) {
      // 変換されていないHEIC画像の場合（フォールバック）
      return Stack(
        children: [
          // 多段階色補正でHEIC特有の緑色問題を解決
          Positioned.fill(
            child: ColorFiltered(
              // 第1段階: 基本的な色空間補正
              colorFilter: const ColorFilter.matrix([
                1.5, -0.6, 0.1, 0.0, 0.0,  // R = 1.5*R - 0.6*G + 0.1*B (赤強化、緑大幅抑制)
                -0.4, 0.2, 0.0, 0.0, 0.0,  // G = -0.4*R + 0.2*G (緑を大幅に抑制)
                0.3, -0.5, 1.6, 0.0, 0.0,  // B = 0.3*R - 0.5*G + 1.6*B (青強化)
                0.0, 0.0, 0.0, 1.0, 0.0,   // A = A
              ]),
              child: ColorFiltered(
                // 第2段階: 温度とコントラスト調整
                colorFilter: const ColorFilter.matrix([
                  1.2, 0.0, 0.0, 0.0, 15.0,  // R微調整+明度
                  0.0, 0.3, 0.0, 0.0, -10.0, // G更に抑制+暗度
                  0.0, 0.0, 1.3, 0.0, 10.0,  // B強化+明度
                  0.0, 0.0, 0.0, 1.0, 0.0,   // A維持
                ]),
                child: Image.file(
                  imageFile,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_fix_high, color: Colors.orange, size: 48),
                          SizedBox(height: 8),
                          Text(
                            'HEIC画像の色補正を適用中\n\n'
                            '画像は正常にアップロードされます',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // HEIC色補正バッジ
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.blue.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_fix_high,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '色補正済',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 下部に色補正情報メッセージ
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                '⚠️ HEIC→JPEG変換に失敗しました\n'
                '色補正を適用していますが、JPEG形式での再撮影をお勧めします',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    } else {
      // 通常の画像形式（JPEG/PNG等）の場合はそのまま表示
      return Image.file(
        imageFile,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[300],
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, color: Colors.red, size: 48),
                SizedBox(height: 8),
                Text(
                  '画像の表示に\n問題があります',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  // 画像プレビューWidget
  Widget _buildImagePreview() {
    if (_selectedImage == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_alt,
            color: Colors.grey[600],
            size: 32,
          ),
          const SizedBox(height: 4),
          Text(
            '画像を選択',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    if (kIsWeb && _selectedImage is Uint8List) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: Image.memory(_selectedImage, fit: BoxFit.cover, width: 100, height: 100),
      );
    } else if (_selectedImage is File) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: Image.file(_selectedImage, fit: BoxFit.cover, width: 100, height: 100),
      );
    } else {
      return const Icon(Icons.error, color: Colors.red);
    }
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
          title: const Text(
            'グループ作成',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.pink[400],
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          // actions削除
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // グループ画像選択
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                        border: Border.all(
                          color: Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: _buildImagePreview(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // グループ名
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'グループ名 *',
                    hintText: 'グループの名前を入力してください',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.pink[400]!),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'グループ名を入力してください';
                    }
                    if (value.trim().length > 30) {
                      return 'グループ名は30文字以内で入力してください';
                    }
                    return null;
                  },
                  maxLength: 30,
                ),
                const SizedBox(height: 16),

                // グループ説明
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'グループ説明',
                    hintText: 'グループの説明を入力してください（任意）',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.pink[400]!),
                    ),
                  ),
                  maxLines: 3,
                  maxLength: 200,
                ),
                const SizedBox(height: 24),

                // プライベートグループ設定
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'プライベートグループ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '招待されたユーザーのみが参加できます',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isPrivate,
                            onChanged: (value) {
                              setState(() {
                                _isPrivate = value;
                              });
                            },
                            activeColor: Colors.pink[400],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 最大人数設定
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '最大人数',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: _maxMembers,
                        decoration: InputDecoration(
                          hintText: '最大人数を選択',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: List.generate(30, (i) => i + 1).map((num) {
                          return DropdownMenuItem(
                            value: num,
                            child: Text('$num 人'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _maxMembers = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // カテゴリ選択
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'カテゴリ（任意）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'グループの興味のあるカテゴリを選択してください',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          hintText: 'カテゴリを選択',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: _categories.map((category) {
                          return DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 都道府県選択
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '都道府県（任意）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'グループの活動エリアを選択してください',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedPrefecture,
                        decoration: InputDecoration(
                          hintText: '都道府県を選択',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
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
                            // 都道府県が変更されたら最寄駅をリセット
                            _selectedNearestStation = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 最寄駅選択（都道府県が選択されている場合のみ）
                if (_selectedPrefecture != null && _stationsByPrefecture.containsKey(_selectedPrefecture))
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '最寄駅（任意）',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'グループの活動の最寄駅を選択してください',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedNearestStation,
                          decoration: InputDecoration(
                            hintText: '最寄駅を選択',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items: _stationsByPrefecture[_selectedPrefecture]!.map((station) {
                            return DropdownMenuItem(
                              value: station,
                              child: Text(station),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedNearestStation = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),

                // ハッシュタグ選択
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ハッシュタグ（任意）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'グループの特徴や興味を表すハッシュタグを選択してください',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // 選択されたハッシュタグの表示
                      if (_selectedTags.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedTags.map((tag) {
                            return Chip(
                              label: Text(tag),
                              onDeleted: () {
                                setState(() {
                                  _selectedTags.remove(tag);
                                });
                              },
                              backgroundColor: Colors.pink[100],
                              deleteIconColor: Colors.pink[700],
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // ハッシュタグ選択ボタン
                      OutlinedButton.icon(
                        onPressed: _showHashtagSelectionDialog,
                        icon: const Icon(Icons.tag),
                        label: Text(_selectedTags.isEmpty ? 'ハッシュタグを選択' : 'ハッシュタグを追加'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.pink[400],
                          side: BorderSide(color: Colors.pink[400]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 作成ボタン
                ElevatedButton(
                  onPressed: _isCreating ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink[400],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'グループを作成',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 