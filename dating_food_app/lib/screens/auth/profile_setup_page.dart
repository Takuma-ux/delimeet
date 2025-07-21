import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'login_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ProfileSetupPage extends StatefulWidget {
  final String authMethod;
  final Map<String, dynamic>? authData; // 認証から取得したデータ
  
  const ProfileSetupPage({
    super.key, 
    required this.authMethod,
    this.authData,
  });

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  // 重複実行防止フラグ
  bool _isRegistering = false;
  
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
  dynamic _selectedImage; // Web: XFile, モバイル: File
  Uint8List? _webImageBytes;
  String? _currentImageUrl;

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

  // マッチしたい人の特徴
  String? _selectedPreferredAgeRange;
  String? _selectedPaymentPreference;
  String? _selectedPreferredGender;

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

  @override
  void initState() {
    super.initState();
    _preloadDataFromAuth();
  }

  /// 🔄 HEIC画像をJPEGに変換
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
    _pageController.dispose();
    super.dispose();
  }

  void _preloadDataFromAuth() {
    // 認証から取得したデータを事前に設定
    if (widget.authData != null) {
      final authData = widget.authData!;
      
      // 名前の事前設定
      if (authData['displayName'] != null && authData['displayName'].toString().isNotEmpty) {
        _nameController.text = authData['displayName'];
      }
      
      // その他のデータがあれば設定
      // 例：Googleアカウントからの情報、LINEプロフィールからの情報など
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('プロフィール設定 (${_currentPage + 1}/7)'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight,
          ),
          child: IntrinsicHeight(
            child: Column(
              children: [
                // プログレスバー
                Container(
                  padding: const EdgeInsets.all(16),
                  child:                   LinearProgressIndicator(
                    value: (_currentPage + 1) / 7,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.pink),
                  ),
                ),
                // ページビュー
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (page) {
                      setState(() {
                        _currentPage = page;
                      });
                    },
                    physics: const NeverScrollableScrollPhysics(), // 横スライド禁止
                    children: [
                      _buildNamePage(),
                      _buildGenderBirthPage(),
                      _buildLocationOccupationPage(),
                      _buildPreferencesPage(),
                      _buildSchoolAndPrivacyPage(),
                      _buildMatchingPreferencesPage(),
                      _buildConfirmationPage(),
                    ],
                  ),
                ),
                // ナビゲーションボタン
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: const Text('戻る'),
                          ),
                        ),
                      if (_currentPage > 0) const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_canProceed() && !_isRegistering) ? _handleNext : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink,
                            foregroundColor: Colors.white,
                          ),
                          child: _isRegistering && _currentPage == 4
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('登録中...'),
                                  ],
                                )
                              : Text(_currentPage == 4 ? '完了' : '次へ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNamePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'プロフィールを設定しましょう',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'お名前とプロフィール画像を設定してください',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),
          
          // プロフィール画像セクション
          _buildProfileImageSection(),
          
          const SizedBox(height: 32),
          
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'お名前',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          
          const SizedBox(height: 24),
          
          TextField(
            controller: _bioController,
            decoration: const InputDecoration(
              labelText: '自己紹介文',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit),
              hintText: 'あなたについて教えてください...',
            ),
            maxLines: 3,
            maxLength: 500,
            textInputAction: TextInputAction.done,
            onEditingComplete: () {
              FocusScope.of(context).unfocus();
            },
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderBirthPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '性別と生年月日を\n教えてください',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 32),
          
          // 性別選択
          const Text(
            '性別',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _genders.map((gender) {
              return ChoiceChip(
                label: Text(gender),
                selected: _selectedGender == gender,
                onSelected: (selected) {
                  setState(() {
                    _selectedGender = selected ? gender : null;
                  });
                },
                selectedColor: Colors.pink.shade100,
              );
            }).toList(),
          ),
          
          const SizedBox(height: 24),
          
          // 生年月日選択
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
          
          // 18歳未満の警告メッセージ
          if (_birthDate != null && !_isOver18())
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '18歳以上である必要があります',
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationOccupationPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'お住まいと職業を\n教えてください',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 32),
          
          // 都道府県選択
          const Text(
            '都道府県',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedPrefecture,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on),
            ),
            hint: const Text('都道府県を選択'),
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
          
          const SizedBox(height: 24),
          
          // 職業選択
          const Text(
            '職業',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedOccupation,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.work),
            ),
            hint: const Text('職業を選択'),
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
          
          const SizedBox(height: 24),
          
          // 土日休み
          Row(
            children: [
              const Text(
                '土日はお休みですか？',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Switch(
                value: _weekendOff,
                onChanged: (value) {
                  setState(() {
                    _weekendOff = value;
                  });
                },
                activeColor: Colors.pink,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '好きな料理カテゴリを\n選択してください',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '複数選択可能です',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          // WrapでChipを左詰め・折り返し表示
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _categories.map((category) {
                  final isSelected = _selectedCategories.contains(category);
                  return FilterChip(
                    label: Text(
                      category,
                      style: const TextStyle(fontSize: 14),
                    ),
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
                    selectedColor: Colors.pink.shade100,
                    checkmarkColor: Colors.pink,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolAndPrivacyPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '学校設定と\nプライバシー設定',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '学校情報と公開設定を選択してください（任意）',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const Text(
                    '学校種別',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _selectedSchoolType,
                    decoration: const InputDecoration(
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
                  
                  const SizedBox(height: 24),
                  
                  // プライバシー設定
                  const Text(
                    'プライバシー設定',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  // 学校名表示設定
                  SwitchListTile(
                    title: const Text('学校名を表示する'),
                    subtitle: const Text('プロフィールに学校名を表示します'),
                    value: _showSchool,
                    onChanged: (value) {
                      setState(() {
                        _showSchool = value;
                      });
                    },
                  ),
                  
                  // 身内バレ防止機能
                  SwitchListTile(
                    title: const Text('身内バレ防止'),
                    subtitle: const Text('同じ学校の人から見えなくします'),
                    value: _hideFromSameSchool,
                    onChanged: (value) {
                      setState(() {
                        _hideFromSameSchool = value;
                      });
                    },
                  ),
                  
                  // いいね限定表示機能
                  SwitchListTile(
                    title: const Text('いいね限定表示'),
                    subtitle: const Text('いいねした人にのみ表示されます'),
                    value: _visibleOnlyIfLiked,
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
        ],
      ),
    );
  }

  Widget _buildMatchingPreferencesPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'マッチング設定を\n選択してください',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'あなたのマッチング設定を選択してください',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          
          // 年齢範囲選択
          const Text(
            '年齢範囲',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _selectedPreferredAgeRange,
            decoration: const InputDecoration(
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
                  child: Text(range),
                );
              }).toList(),
            ],
            onChanged: (value) {
              setState(() {
                _selectedPreferredAgeRange = value;
              });
            },
          ),
          
          const SizedBox(height: 24),
          
          // 支払い方法選択
          const Text(
            '支払い方法',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _selectedPaymentPreference,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.attach_money),
            ),
            hint: const Text('支払い方法を選択'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('未設定'),
              ),
              ..._paymentPreferences.map((label) {
                return DropdownMenuItem<String?>(
                  value: label,
                  child: Text(_paymentPreferenceLabels[
                      _paymentPreferences.indexOf(label)]),
                );
              }).toList(),
            ],
            onChanged: (value) {
              setState(() {
                _selectedPaymentPreference = value;
              });
            },
          ),
          
          const SizedBox(height: 24),
          
          // 希望性別選択
          const Text(
            '希望性別',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: _selectedPreferredGender,
            decoration: const InputDecoration(
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
        ],
      ),
    );
  }

  Widget _buildConfirmationPage() {
    final age = _birthDate != null 
        ? DateTime.now().year - _birthDate!.year 
        : 0;
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'プロフィール確認',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '内容に間違いがないか確認してください',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildConfirmationItem('認証方法', _getAuthMethodName()),
                      _buildConfirmationItem('お名前', _nameController.text),
                      if (_bioController.text.isNotEmpty)
                        _buildConfirmationItem('自己紹介', _bioController.text),
                      _buildConfirmationItem('年齢', '${age}歳'),
                      _buildConfirmationItem('性別', _selectedGender ?? ''),
                      _buildConfirmationItem('都道府県', _selectedPrefecture ?? ''),
                      _buildConfirmationItem('職業', _selectedOccupation ?? ''),
                      _buildConfirmationItem('土日休み', _weekendOff ? 'はい' : 'いいえ'),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text(
                                '好きなカテゴリ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _selectedCategories.isNotEmpty
                                  ? Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: _selectedCategories.map((cat) => Chip(
                                        label: Text(cat, style: const TextStyle(fontSize: 14)),
                                        backgroundColor: Colors.pink.shade50,
                                      )).toList(),
                                    )
                                  : const Text('未選択', style: TextStyle(fontSize: 16)),
                            ),
                          ],
                        ),
                      ),
                      _buildConfirmationItem('希望年齢範囲', _selectedPreferredAgeRange ?? '未設定'),
                      _buildConfirmationItem('支払い方法', _getPaymentPreferenceLabel()),
                      _buildConfirmationItem('希望性別', _selectedPreferredGender ?? '未設定'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  String _getAuthMethodName() {
    switch (widget.authMethod) {
      case 'phone':
        return '電話番号';
      case 'apple':
        return 'Apple ID';
      case 'google':
        return 'Google';
      case 'email':
        return 'メールアドレス';
      case 'line':
        return 'LINE';
      default:
        return widget.authMethod;
    }
  }

  String _getPaymentPreferenceLabel() {
    if (_selectedPaymentPreference == null) {
      return '未設定';
    }
    final index = _paymentPreferences.indexOf(_selectedPaymentPreference!);
    return _paymentPreferenceLabels[index];
  }

  bool _canProceed() {
    switch (_currentPage) {
      case 0:
        return _nameController.text.isNotEmpty;
      case 1:
        return _selectedGender != null && _birthDate != null && _isOver18();
      case 2:
        return _selectedPrefecture != null && _selectedOccupation != null;
      case 3:
        return _selectedCategories.isNotEmpty; // 1つ以上選択必須
      case 4:
        return true; // 学校・プライバシー設定は任意
      case 5:
        return true; // マッチング設定は任意設定
      case 6:
        return true; // 確認ページ
      default:
        return false;
    }
  }

  void _handleNext() {
    if (_currentPage < 6) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeRegistration();
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
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
                      _webImageBytes = null;
                      _currentImageUrl = null;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

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
          // Web: XFileをそのまま保持し、プレビュー用にbytesも保持
          setState(() {
            _selectedImage = image;
            _webImageBytes = null;
          });
          final bytes = await image.readAsBytes();
          if (mounted) {
            setState(() {
              _webImageBytes = bytes;
            });
          }
        } else {
          // モバイル: Fileに変換
          final File originalFile = File(image.path);
          
          // ファイル拡張子をチェック
          final String extension = image.path.toLowerCase();
          final bool isHeic = extension.endsWith('.heic') || extension.endsWith('.heif');
          final bool isFromImagePicker = image.path.contains('image_picker_');
          
          if (isHeic || isFromImagePicker) {
            final convertedFile = await _convertHeicToJpeg(originalFile);
            if (mounted) {
              setState(() {
                _selectedImage = convertedFile ?? originalFile;
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _selectedImage = originalFile;
              });
            }
          }
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

  // プロフィール画像表示部分も修正
  Widget _buildProfileImageSection() {
    return Center(
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
                border: Border.all(
                  color: Colors.pink,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _selectedImage != null
                    ? (kIsWeb
                        ? (_webImageBytes != null
                            ? Image.memory(
                                _webImageBytes!,
                                fit: BoxFit.cover,
                                width: 120,
                                height: 120,
                              )
                            : const CircularProgressIndicator())
                        : Image.file(
                            _selectedImage as File,
                            fit: BoxFit.cover,
                            width: 120,
                            height: 120,
                          ))
                    : _currentImageUrl != null
                        ? Image.network(
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
                          )
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
            label: Text(_selectedImage == null ? '画像を追加' : '画像を変更'),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedImage == null ? '画像は後からでも設定できます' : '素敵な写真ですね！',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) {
      return null;
    }
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

  void _completeRegistration() async {
    // 重複実行防止チェック
    if (_isRegistering) {
      return;
    }
    
    // 処理中フラグを設定
    setState(() {
      _isRegistering = true;
    });
    
    try {
      
      // Firebase Authの認証状態を詳細確認
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        throw Exception('ユーザーが認証されていません');
      }


      // IDトークンを明示的に取得して確認
      final idToken = await user.getIdToken(true); // 強制更新
      
      // ローディング開始
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('プロフィールを登録中...'),
            ],
          ),
        ),
      );

      // 画像をアップロード
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
      }

      // 年齢計算
      final age = _birthDate != null 
          ? DateTime.now().year - _birthDate!.year 
          : 18;

      String? email;
      String? phoneNumber;

      // プロバイダーデータから情報を取得
      for (final provider in user.providerData) {
        if (provider.email != null) {
          email = provider.email;
        }
        if (provider.phoneNumber != null) {
          phoneNumber = provider.phoneNumber;
        }
      }
      
      // メインユーザーからも取得
      email = email ?? user.email;
      phoneNumber = phoneNumber ?? user.phoneNumber;


      // Firebase Functionsのインスタンス確認
      final functions = FirebaseFunctions.instance;
      
      // Firebase Functionsにデータ送信
      final callable = functions.httpsCallable('createUserProfile');
      
      final data = {
        'name': _nameController.text,
        'bio': _bioController.text,
        'age': age,
        'birth_date': _birthDate?.toIso8601String(), // ISO 8601形式で送信
        'gender': _selectedGender,
        'prefecture': _selectedPrefecture,
        'occupation': _selectedOccupation,
        'weekend_off': _weekendOff,
        'favorite_categories': _selectedCategories,
        'authMethod': widget.authMethod,
        'email': email,
        'phoneNumber': phoneNumber,
        'image_url': imageUrl, // Firebase Storageのダウンロードリンク
        'preferred_age_range': _selectedPreferredAgeRange,
        'payment_preference': _selectedPaymentPreference,
        'preferred_gender': _selectedPreferredGender,
        'school_id': _selectedSchoolId,
        'show_school': _showSchool,
        'hide_from_same_school': _hideFromSameSchool,
        'visible_only_if_liked': _visibleOnlyIfLiked,
      };
      
      
      // リトライ機能付きで呼び出し
      HttpsCallableResult? result;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount < maxRetries) {
        try {
          result = await callable.call(data).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('プロフィール登録がタイムアウトしました');
            },
          );
          
          
          break; // 成功したらループ終了
          
        } catch (e) {
          retryCount++;
          if (retryCount >= maxRetries) {
            throw e; // 最大試行回数に達したらエラーを再スロー
          }
          
          // 認証トークンを再取得してリトライ
          await user.getIdToken(true);
          await Future.delayed(const Duration(seconds: 1)); // 1秒待機
        }
      }

      Navigator.pop(context); // ローディング終了


      // SharedPreferencesでプロフィール設定完了フラグを保存（HomePage遷移前に実行）
      final prefs = await SharedPreferences.getInstance();
      final flagKey = 'profile_setup_completed_${user.uid}';
      
      // フラグを保存
      final saveResult = await prefs.setBool(flagKey, true);
      
      // 保存されたかを確認
      final savedValue = prefs.getBool(flagKey) ?? false;
      
      
      if (!savedValue) {
        // 再試行
        await prefs.setBool(flagKey, true);
        final retryValue = prefs.getBool(flagKey) ?? false;
      }
      

      // 成功メッセージ
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 プロフィール登録が完了しました！'),
          backgroundColor: Colors.green,
        ),
      );

      // おすすめデータの取得を待つ
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('おすすめデータを準備中...'),
            ],
          ),
        ),
      );

      final ready = await _waitForRecommendationsReady();

      Navigator.pop(context); // ローディング終了

      if (!ready) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('おすすめデータの取得に失敗しました。しばらくしてから再度お試しください。'),
            backgroundColor: Colors.red,
          ),
        );
        // 必要ならここでreturn;
      }

      // Cloud Functions呼び出し後にIDトークンを再取得し、サインアウトされていないか確認
      try {
        await user.reload(); // ユーザー情報を再読み込み
        await user.getIdToken(true); // トークンを強制リフレッシュ
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('認証の更新に失敗しました。再度ログインしてください。'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
          return;
        }
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // サインアウトされていたら、エラーメッセージを表示してLoginPageに遷移
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('認証セッションが切れました。再度ログインしてください。'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
        return;
      }

      // ホーム画面に遷移
      await _navigateToHome();

    } catch (e) {
      Navigator.pop(context); // ローディング終了
      
      String errorMessage = 'プロフィール登録に失敗しました';
      
      // Firebase Functions エラーの詳細処理
      if (e is FirebaseFunctionsException) {
        
        switch (e.code) {
          case 'already-exists':
            errorMessage = 'このアカウントのプロフィールは既に作成されています。アプリを再起動してください。';
            // 既存ユーザーの場合、フラグを設定してメイン画面に遷移
            final prefs = await SharedPreferences.getInstance();
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await prefs.setBool('profile_setup_completed_${user.uid}', true);
              await _navigateToHome();
              return;
            }
            break;
          case 'unauthenticated':
            errorMessage = 'ユーザー認証が無効です。再度ログインしてください。';
            break;
          case 'invalid-argument':
            errorMessage = '入力データに問題があります。すべての項目を正しく入力してください。';
            break;
          default:
            errorMessage = e.message ?? 'プロフィール登録に失敗しました';
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $errorMessage'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      // 処理完了時にフラグをリセット
      if (mounted) {
        setState(() {
          _isRegistering = false;
        });
      }
    }
  }

  Future<bool> _waitForRecommendationsReady() async {
    try {
      
      // ユーザー情報を再取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return false;
      }
      
      // トークンを強制リフレッシュ
      await user.reload();
      final token = await user.getIdToken(true);

      // データ取得を試行
      final functions = FirebaseFunctions.instance;
      final usersResult = await functions.httpsCallable('getRecommendedUsers').call();
      final users = List.from(usersResult.data ?? []);

      final restaurantsResult = await functions.httpsCallable('searchRestaurants').call({
        'category': '和食',
        'userId': user.uid,
      });
      final restaurants = restaurantsResult.data is Map && restaurantsResult.data['restaurants'] != null
          ? List.from(restaurantsResult.data['restaurants'])
          : List.from(restaurantsResult.data ?? []);

      return users.isNotEmpty || restaurants.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _navigateToHome() async {
    try {
      
      // データ取得を待機
      final isReady = await _waitForRecommendationsReady();
      if (!isReady) {
        return;
      }
      
      
      if (!mounted) return;
      
      // 画面遷移（pushReplacementを使用）
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const HomePage(),
        ),
      );
    } catch (e) {
    }
  }

  Future<void> _checkSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      String debugInfo = 'SharedPreferences確認:\n';
      
      if (user != null) {
        final flagKey = 'profile_setup_completed_${user.uid}';
        final isCompleted = prefs.getBool(flagKey) ?? false;
        debugInfo += '・UID: ${user.uid}\n';
        debugInfo += '・フラグ: $flagKey = $isCompleted\n';
      } else {
        debugInfo += '・ユーザー未認証\n';
      }
      
      final allKeys = prefs.getKeys();
      debugInfo += '・全キー数: ${allKeys.length}\n';
      for (final key in allKeys) {
        if (key.startsWith('profile_setup_completed_')) {
          debugInfo += '・$key = ${prefs.getBool(key)}\n';
        }
      }
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔍 デバッグ情報'),
            content: SingleChildScrollView(
              child: Text(debugInfo),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _setProfileCompletedFlag() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('profile_setup_completed_${user.uid}', true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ プロフィール設定完了フラグを手動設定しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ ユーザーが認証されていません'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // デバッグ用ログアウト処理を一時的に無効化
  Future<void> _debugLogout() async {
    // 一時的にコメントアウト
    /*
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 ログアウトしました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      // AuthWrapperが認証状態の変化を検知して自動的にLoginPageに遷移される
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ログアウト失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    */
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