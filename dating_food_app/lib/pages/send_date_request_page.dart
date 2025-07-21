import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../models/date_request_model.dart';
import '../models/restaurant_model.dart';
import '../services/web_image_helper.dart';

// 支払いオプション列挙型
enum PaymentOption {
  treat('おごります', '💸', Color(0xFF4CAF50)),
  split('割り勘', '🤝', Color(0xFF2196F3)),
  discuss('相談', '💬', Color(0xFFFF9800));

  const PaymentOption(this.displayName, this.emoji, this.color);
  final String displayName;
  final String emoji;
  final Color color;
}

class SendDateRequestPage extends StatefulWidget {
  final String matchId;
  final String partnerId;
  final String partnerName;
  final String? partnerImageUrl;

  const SendDateRequestPage({
    super.key,
    required this.matchId,
    required this.partnerId,
    required this.partnerName,
    this.partnerImageUrl,
  });

  @override
  State<SendDateRequestPage> createState() => _SendDateRequestPageState();
}

class _SendDateRequestPageState extends State<SendDateRequestPage> {
  final _messageController = TextEditingController();
  
  // 3つの候補日時（グループリクエストと同じ形式）
  final List<DateTime?> _selectedDates = [null, null, null];
  final List<TimeOfDay?> _selectedTimes = [null, null, null];
  
  // プルダウン用の日付・時間リスト
  List<DateTime> _availableDates = [];
  List<TimeOfDay> _availableTimes = [];
  
  List<Restaurant> _favoriteRestaurants = [];
  Restaurant? _selectedRestaurant;
  List<Restaurant> _additionalRestaurants = []; // 追加店舗選択
  PaymentOption _selectedPaymentOption = PaymentOption.discuss;
  bool _isLoading = false;
  bool _isLoadingRestaurants = true;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFavoriteRestaurants();
    _generateDateAndTimeOptions();
  }
  
  void _generateDateAndTimeOptions() {
    // 今日から30日間の日付を生成
    _availableDates = List.generate(30, (index) => 
        DateTime.now().add(Duration(days: index)));
    
    // 8:00から23:30まで30分刻みで時間を生成
    _availableTimes = [];
    for (int hour = 8; hour <= 23; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        _availableTimes.add(TimeOfDay(hour: hour, minute: minute));
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadFavoriteRestaurants() async {
    try {
      setState(() {
        _isLoadingRestaurants = true;
      });

      final callable = FirebaseFunctions.instance.httpsCallable('getFavoriteRestaurants');
      final result = await callable.call();

      // Firebase Functionsからのレスポンスを適切に処理
      final Map<String, dynamic> responseData = Map<String, dynamic>.from(result.data);
      final List<dynamic> restaurantData = responseData['restaurants'] ?? [];

      final restaurants = restaurantData.map((data) {
        final Map<String, dynamic> restaurantMap = Map<String, dynamic>.from(data);
        return Restaurant.fromJson(restaurantMap);
      }).toList();

      setState(() {
        _favoriteRestaurants = restaurants;
        _isLoadingRestaurants = false;
      });
    } catch (e) {
      
      setState(() {
        _isLoadingRestaurants = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('お気に入り店舗の取得に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 価格レベルに応じた¥マークを生成
  String _getPriceLevelDisplay(int? priceLevel) {
    if (priceLevel == null) return '¥¥¥';
    return '¥' * priceLevel;
  }

  // 価格レベルに応じた色を取得
  Color _getPriceLevelColor(int? priceLevel) {
    switch (priceLevel) {
      case 1: return Colors.green;
      case 2: return Colors.lightGreen;
      case 3: return Colors.orange;
      case 4: return Colors.deepOrange;
      case 5: return Colors.red;
      default: return Colors.grey;
    }
  }

  /// 営業時間チェック機能
  bool _isRestaurantOpen(Map<String, dynamic>? operatingHoursData, DateTime dateTime) {
    
    if (operatingHoursData == null) {
      return false; // 営業時間データがない場合は営業時間外として扱う
    }

    try {
      final List<dynamic>? schedules = operatingHoursData['operating_hours'] as List<dynamic>?;
      if (schedules == null || schedules.isEmpty) {
        return false;
      }

      final weekday = dateTime.weekday % 7; // Flutterの曜日 (月=1, 日=7) を変換 (月=1, 日=0)
      final timeString = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      
      
      for (int i = 0; i < schedules.length; i++) {
        final schedule = schedules[i];
        final days = List<int>.from(schedule['days'] ?? []);
        final openTime = schedule['open_time'] as String?;
        final closeTime = schedule['close_time'] as String?;
        
        
        if (days.contains(weekday) && openTime != null && closeTime != null) {
          // 時間比較ロジック
          final isWithinRange = _isTimeWithinRange(timeString, openTime, closeTime);
          if (isWithinRange) {
            return true;
          }
        } else if (days.contains(weekday)) {
        }
      }
      return false;
    } catch (e) {
      return false; // エラーの場合も営業時間外として扱う
    }
  }

  /// 時間範囲チェック（営業時間内かどうか）
  bool _isTimeWithinRange(String currentTime, String openTime, String closeTime) {
    try {
      final current = _parseTime(currentTime);
      final open = _parseTime(openTime);
      var close = _parseTime(closeTime);
      
      // 翌日にまたがる場合（例：22:00-02:00）
      if (close < open) {
        close += 24 * 60; // 翌日に調整
        if (current < open) {
          // 深夜の場合、翌日として扱う
          return current + 24 * 60 <= close;
        }
      }
      
      return current >= open && current <= close;
    } catch (e) {
      return true;
    }
  }

  /// 時間文字列を分に変換（例："14:30" → 870）
  int _parseTime(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) throw FormatException('Invalid time format: $timeString');
    
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return hour * 60 + minute;
  }

  /// 店舗の営業時間を取得
  String _getOperatingHoursDisplay(Map<String, dynamic>? operatingHoursData, int weekday) {
    if (operatingHoursData == null) {
      return '営業時間情報なし';
    }

    try {
      final List<dynamic>? schedules = operatingHoursData['operating_hours'] as List<dynamic>?;
      if (schedules == null || schedules.isEmpty) {
        return '営業時間情報なし';
      }
      
      for (final schedule in schedules) {
        final days = List<int>.from(schedule['days'] ?? []);
        final openTime = schedule['open_time'] as String?;
        final closeTime = schedule['close_time'] as String?;
        
        if (days.contains(weekday) && openTime != null && closeTime != null) {
          return '$openTime - $closeTime';
        }
      }
      
      return '定休日';
    } catch (e) {
      return '営業時間情報なし';
    }
  }

  /// 営業時間警告をチェック
  List<String> _checkOperatingHoursWarnings() {
    if (_selectedRestaurant == null) return [];
    
    List<String> warnings = [];
    
    for (int i = 0; i < 3; i++) {
      if (_selectedDates[i] != null && _selectedTimes[i] != null) {
        final dateTime = DateTime(
          _selectedDates[i]!.year,
          _selectedDates[i]!.month,
          _selectedDates[i]!.day,
          _selectedTimes[i]!.hour,
          _selectedTimes[i]!.minute,
        );
        
        if (!_isRestaurantOpen(_selectedRestaurant!.operatingHours, dateTime)) {
          final weekday = dateTime.weekday % 7;
          final operatingHours = _getOperatingHoursDisplay(_selectedRestaurant!.operatingHours, weekday);
          final formattedDateTime = DateFormat('MM/dd(E) HH:mm', 'ja').format(dateTime);
          warnings.add('$formattedDateTime は営業時間外です（営業時間: $operatingHours）');
        }
      }
    }
    
    return warnings;
  }

  /// 営業時間警告をUIウィジェットとして構築
  List<Widget> _buildOperatingHoursWarnings() {
    final warnings = _checkOperatingHoursWarnings();
    List<Widget> widgets = [];
    
    // 警告メッセージの表示
    if (warnings.isNotEmpty) {
      widgets.add(
        Column(
          children: warnings.map((warning) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ),
      );
    }
    
    return widgets;
  }

  /// 追加レストランの営業時間警告を構築
  List<Widget> _buildAdditionalRestaurantWarnings(Restaurant restaurant) {
    List<Widget> warnings = [];
    
    for (int i = 0; i < 3; i++) {
      if (_selectedDates[i] != null && _selectedTimes[i] != null) {
        final dateTime = DateTime(
          _selectedDates[i]!.year,
          _selectedDates[i]!.month,
          _selectedDates[i]!.day,
          _selectedTimes[i]!.hour,
          _selectedTimes[i]!.minute,
        );

        if (!_isRestaurantOpen(restaurant.operatingHours, dateTime)) {
          final weekday = dateTime.weekday % 7;
          final operatingHours = _getOperatingHoursDisplay(restaurant.operatingHours, weekday);
          final formattedDateTime = DateFormat('MM/dd(E) HH:mm', 'ja').format(dateTime);
          
          warnings.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange.shade600, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$formattedDateTime は営業時間外です（営業時間: $operatingHours）',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }
    
    return warnings;
  }

  // グループリクエストと同じカード形式の日程選択UI
  Widget _buildDateTimeSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '希望日時（最大3つ）',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '相手が選択して日程を決定します',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        
        // カード形式で各候補を表示
        for (int i = 0; i < 3; i++) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '候補 ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<DateTime>(
                          value: _selectedDates[i],
                          decoration: const InputDecoration(
                            labelText: '日付選択',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          style: const TextStyle(fontSize: 12, color: Colors.black),
                          items: _availableDates.map((date) {
                            return DropdownMenuItem<DateTime>(
                              value: date,
                              child: Text(
                                DateFormat('MM/dd(E)', 'ja').format(date),
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (date) {
                            setState(() {
                              _selectedDates[i] = date;
                              // 日時変更時に営業時間警告を再チェック
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<TimeOfDay>(
                          value: _selectedTimes[i],
                          decoration: const InputDecoration(
                            labelText: '時間選択',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          style: const TextStyle(fontSize: 12, color: Colors.black),
                          items: _availableTimes.map((time) {
                            return DropdownMenuItem<TimeOfDay>(
                              value: time,
                              child: Text(
                                time.format(context),
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (time) {
                            setState(() {
                              _selectedTimes[i] = time;
                              // 時間変更時に営業時間警告を再チェック
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_selectedDates[i] != null || _selectedTimes[i] != null)
                        SizedBox(
                          width: 32,
                          child: IconButton(
                            onPressed: () => _clearDateTime(i),
                            icon: const Icon(Icons.clear, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  void _clearDateTime(int index) {
    setState(() {
      _selectedDates[index] = null;
      _selectedTimes[index] = null;
    });
  }

  Widget _buildRestaurantSelection() {
    if (_isLoadingRestaurants) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_favoriteRestaurants.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.restaurant, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'お気に入り店舗がありません',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'まずは店舗にいいねをしてお気に入りに追加してください',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('戻る'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'レストラン選択（最初の1つで日程を決めます）',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_selectedRestaurant != null) ...[
          Card(
            color: Colors.pink.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.pink, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                        ),
                        child: _selectedRestaurant!.displayImageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: WebImageHelper.buildRestaurantImage(
                                  _selectedRestaurant!.displayImageUrl,
                                  width: 60,
                                  height: 60,
                                ),
                              )
                            : const Icon(Icons.restaurant, size: 30),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedRestaurant!.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedRestaurant!.displayCategory,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  _selectedRestaurant!.displayPriceRange,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _getPriceLevelColor(_selectedRestaurant!.priceLevel),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_selectedRestaurant!.displayLocation.isNotEmpty) ...[
                                  const Icon(Icons.location_on, size: 12, color: Colors.grey),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      _selectedRestaurant!.displayLocation,
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _selectedRestaurant = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  // 営業時間警告表示
                  ..._buildOperatingHoursWarnings(),
                ],
              ),
            ),
          ),
        ] else ...[
          OutlinedButton(
            onPressed: _showRestaurantSelection,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant),
                SizedBox(width: 8),
                Text('メインレストランを選択'),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 16),
        
        // 追加店舗選択セクション
        const Text(
          '追加店舗（任意）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          '日程決定後、これらの店舗とメイン店舗で投票を行います',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        
        // 選択済み追加店舗表示
        if (_additionalRestaurants.isNotEmpty) ...[
          for (final restaurant in _additionalRestaurants) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey.shade200,
                      ),
                      child: restaurant.displayImageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: WebImageHelper.buildRestaurantImage(
                                restaurant.displayImageUrl,
                                width: 40,
                                height: 40,
                              ),
                            )
                          : const Icon(Icons.restaurant, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            restaurant.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            restaurant.displayCategory,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _additionalRestaurants.remove(restaurant);
                        });
                      },
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
            // 営業時間警告表示
            ..._buildAdditionalRestaurantWarnings(restaurant),
            const SizedBox(height: 4),
          ],
        ],
        
        OutlinedButton.icon(
          onPressed: _showAdditionalRestaurantSelection,
          icon: const Icon(Icons.add),
          label: Text(_additionalRestaurants.isEmpty 
              ? '追加レストランを選択' 
              : '更に追加（${_additionalRestaurants.length}店舗選択済み）'),
        ),
      ],
    );
  }

  void _showRestaurantSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'メインレストランを選択',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _favoriteRestaurants.length,
                  itemBuilder: (context, index) {
                    final restaurant = _favoriteRestaurants[index];
                    return ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                        ),
                        child: restaurant.displayImageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: WebImageHelper.buildRestaurantImage(
                                  restaurant.displayImageUrl,
                                  width: 50,
                                  height: 50,
                                ),
                              )
                            : const Icon(Icons.restaurant, size: 25),
                      ),
                      title: Text(restaurant.name),
                      subtitle: Text(restaurant.displayCategory),
                      onTap: () {
                        setState(() {
                          _selectedRestaurant = restaurant;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdditionalRestaurantSelection() {
    // 既に選択済みの店舗を除外
    final excludedIds = [
      if (_selectedRestaurant != null) _selectedRestaurant!.id,
      ..._additionalRestaurants.map((r) => r.id),
    ];
    
    final availableRestaurants = _favoriteRestaurants
        .where((r) => !excludedIds.contains(r.id))
        .toList();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '追加レストランを選択',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '日程確定後、これらの店舗で投票します',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              if (availableRestaurants.isEmpty) ...[
                const Center(
                  child: Text('選択可能なレストランがありません'),
                ),
              ] else ...[
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: availableRestaurants.length,
                    itemBuilder: (context, index) {
                      final restaurant = availableRestaurants[index];
                      return ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade200,
                          ),
                          child: restaurant.displayImageUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: WebImageHelper.buildRestaurantImage(
                                    restaurant.displayImageUrl,
                                    width: 50,
                                    height: 50,
                                  ),
                                )
                              : const Icon(Icons.restaurant, size: 25),
                        ),
                        title: Text(restaurant.name),
                        subtitle: Text(restaurant.displayCategory),
                        onTap: () {
                          setState(() {
                            _additionalRestaurants.add(restaurant);
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentOptionSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '支払い設定',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: PaymentOption.values.map((option) {
            final isSelected = _selectedPaymentOption == option;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPaymentOption = option;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? option.color.withValues(alpha: 0.1) : Colors.grey.shade100,
                      border: Border.all(
                        color: isSelected ? option.color : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          option.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? option.color : Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _getPaymentOptionDescription(_selectedPaymentOption),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  String _getPaymentOptionDescription(PaymentOption option) {
    switch (option) {
      case PaymentOption.treat:
        return 'あなたが全額支払います';
      case PaymentOption.split:
        return '費用を半分ずつ負担します';
      case PaymentOption.discuss:
        return '当日相談して決めます';
    }
  }

  Widget _buildMessageInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'メッセージ（任意）',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _messageController,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '${widget.partnerName}さんへのメッセージを入力してください',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  bool _canSendRequest() {
    return _selectedRestaurant != null &&
           _selectedDates.any((date) => date != null) &&
           _selectedTimes.any((time) => time != null) &&
           !_isLoading;
  }

  Future<void> _sendDateRequest() async {
    if (!_canSendRequest()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 有効な日時のペアを取得
      final List<DateTime> validDateTimes = [];
      for (int i = 0; i < 3; i++) {
        if (_selectedDates[i] != null && _selectedTimes[i] != null) {
          final dateTime = DateTime(
            _selectedDates[i]!.year,
            _selectedDates[i]!.month,
            _selectedDates[i]!.day,
            _selectedTimes[i]!.hour,
            _selectedTimes[i]!.minute,
          );
          validDateTimes.add(dateTime);
        }
      }

      // 追加店舗のIDリストを作成
      final List<String> additionalRestaurantIds = _additionalRestaurants
          .map((restaurant) => restaurant.id)
          .toList();


      final callable = FirebaseFunctions.instance.httpsCallable('sendDateRequest');
      final requestData = {
        'matchId': widget.matchId,
        'restaurantId': _selectedRestaurant!.id,
        'additionalRestaurantIds': additionalRestaurantIds, // 追加店舗IDを送信
        'message': _messageController.text.trim(),
        'proposedDates': validDateTimes.map((dt) => dt.toIso8601String()).toList(),
        'paymentOption': _selectedPaymentOption.name, // 支払いオプションを追加
        'restaurantOperatingHours': _selectedRestaurant!.operatingHours, // 営業時間情報を追加
        // 詳細な価格・場所情報を追加
        'restaurantLowPrice': _selectedRestaurant!.lowPrice,
        'restaurantHighPrice': _selectedRestaurant!.highPrice,
        'restaurantNearestStation': _selectedRestaurant!.nearestStation,
      };
      
      
      final result = await callable.call(requestData);
      

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('デートリクエストを送信しました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      
      if (mounted) {
        String errorMessage = '送信に失敗しました';
        
        // より詳細なエラー解析
        final errorString = e.toString();
        
        if (errorString.contains('already-exists')) {
          errorMessage = '未回答のデートリクエストが既に存在します';
        } else if (errorString.contains('not-found')) {
          errorMessage = 'マッチまたはレストランが見つかりません';
        } else if (errorString.contains('invalid-argument')) {
          errorMessage = '入力内容に問題があります';
        } else if (errorString.contains('unauthenticated')) {
          errorMessage = 'ログインが必要です';
        } else if (errorString.contains('permission-denied')) {
          errorMessage = 'アクセス権限がありません';
        } else if (errorString.contains('network')) {
          errorMessage = 'ネットワークエラーが発生しました';
        } else {
          errorMessage = '送信に失敗しました: ${errorString.length > 100 ? errorString.substring(0, 100) + "..." : errorString}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 他の部分をタップしたときにキーボードを閉じる
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.partnerName}さんにデートをお誘い'),
          backgroundColor: Colors.pink,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // エラーメッセージ表示
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // 1. 日程選択（最初に移動）
              _buildDateTimeSelection(),
              const SizedBox(height: 24),
              
              // 2. レストラン選択
              _buildRestaurantSelection(),
              const SizedBox(height: 24),
              
              // 3. 支払い設定
              _buildPaymentOptionSelection(),
              const SizedBox(height: 24),
              
              // 4. メッセージ入力
              _buildMessageInput(),
              const SizedBox(height: 32),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _canSendRequest() ? _sendDateRequest : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'デートリクエストを送信',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
          ),
        ),
      ),
    );
  }
} 