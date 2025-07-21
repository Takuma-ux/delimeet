import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert' as convert;
import 'package:url_launcher/url_launcher.dart';
import '../models/restaurant_model.dart';
import '../models/group_model.dart';
import '../services/web_image_helper.dart';

class SendGroupDateRequestPage extends StatefulWidget {
  final Group group;
  final List<String> memberIds;

  const SendGroupDateRequestPage({
    super.key,
    required this.group,
    required this.memberIds,
  });

  @override
  State<SendGroupDateRequestPage> createState() => _SendGroupDateRequestPageState();
}

class _SendGroupDateRequestPageState extends State<SendGroupDateRequestPage> {
  final TextEditingController _messageController = TextEditingController();
  Restaurant? _selectedRestaurant;
  List<Restaurant> _additionalRestaurants = []; // 2段階目の店舗投票用
  
  // 3つの候補日時
  final List<DateTime?> _selectedDates = [null, null, null];
  final List<TimeOfDay?> _selectedTimes = [null, null, null];
  
  // プルダウン用の日付・時間リスト
  List<DateTime> _availableDates = [];
  List<TimeOfDay> _availableTimes = [];
  
  bool _isLoading = false;
  String? _errorMessage;

  List<Restaurant> _restaurants = [];

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
    _generateDateAndTimeOptions();
  }
  
  void _generateDateAndTimeOptions() {
    // 今日から30日間の日付を生成
    _availableDates = List.generate(30, (index) => 
        DateTime.now().add(Duration(days: index)));
    
    // 8:00から23:30まで30分刻みで時間を生成（より幅広い時間帯に対応）
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

  Future<void> _loadRestaurants() async {
    try {
      // いいねしたレストランを取得
      final callable = FirebaseFunctions.instance.httpsCallable('getLikedRestaurants');
      final result = await callable.call();
      
      final List<dynamic> restaurantData = result.data['restaurants'] ?? [];
      
      setState(() {
        _restaurants = restaurantData
            .map((data) => Restaurant.fromMap(Map<String, dynamic>.from(data)))
            .toList();
      });
      
      
    } catch (e) {
    }
  }

  bool _canSendRequest() {
    if (_selectedRestaurant == null) return false;
    
    // 少なくとも1つの日時ペアが必要
    for (int i = 0; i < 3; i++) {
      if (_selectedDates[i] != null && _selectedTimes[i] != null) {
        return true;
      }
    }
    return false;
  }

  /// 価格帯表示（low_price/high_priceベース）
  String _getPriceRangeDisplay(Restaurant restaurant) {
    if (restaurant.lowPrice != null && restaurant.highPrice != null) {
      if (restaurant.lowPrice == restaurant.highPrice) {
        return '${restaurant.lowPrice}円';
      } else {
        return '${restaurant.lowPrice}~${restaurant.highPrice}円';
      }
    } else if (restaurant.lowPrice != null) {
      return '${restaurant.lowPrice}円~';
    } else if (restaurant.highPrice != null) {
      return '~${restaurant.highPrice}円';
    } else if (restaurant.priceRange != null && restaurant.priceRange!.isNotEmpty) {
      return restaurant.priceRange!;
    }
    return '価格未設定';
  }

  /// 場所表示（都道府県 + 最寄駅）
  String _getLocationDisplay(Restaurant restaurant) {
    List<String> locationParts = [];
    if (restaurant.prefecture != null && restaurant.prefecture!.isNotEmpty) {
      locationParts.add(restaurant.prefecture!);
    }
    if (restaurant.nearestStation != null && restaurant.nearestStation!.isNotEmpty) {
      locationParts.add(restaurant.nearestStation!);
    }
    return locationParts.isNotEmpty ? locationParts.join(' • ') : '場所未設定';
  }

  Color _getPriceRangeColor(Restaurant restaurant) {
    // 下限価格に基づいて色を決定
    final lowPrice = restaurant.lowPrice;
    if (lowPrice == null) return Colors.grey[600]!;
    
    if (lowPrice <= 1000) return Colors.green[700]!;
    if (lowPrice <= 2000) return Colors.lightGreen[700]!;
    if (lowPrice <= 3000) return Colors.orange[700]!;
    if (lowPrice <= 5000) return Colors.deepOrange[700]!;
    return Colors.red[700]!;
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: warnings.map((warning) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border.all(color: Colors.orange[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[600], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border.all(color: Colors.orange[300]!),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[600], size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$formattedDateTime は営業時間外です（営業時間: $operatingHours）',
                      style: TextStyle(
                        color: Colors.orange[800],
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

  /// ホットペッパーURLを開く
  Future<void> _launchHotpepperUrl(String? url) async {
    
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ホットペッパーURLが設定されていません'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'URLを開けませんでした: $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URLの起動に失敗しました'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('グループデートリクエスト'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () {
          // キーボードを閉じる
          FocusScope.of(context).unfocus();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // グループ情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'グループ: ${widget.group.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'メンバー: ${widget.memberIds.length}人',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // エラーメッセージ
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  border: Border.all(color: Colors.red[200]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[400]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // 候補日時選択
            const Text(
              '候補日時（最大3つ）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
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
            
            const SizedBox(height: 24),
            
            // レストラン選択
            const Text(
              'レストラン選択（最初の1つで日程を決めます）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
            if (_selectedRestaurant != null) ...[
              Card(
                color: Colors.blue[50],
                child: Column(
                  children: [
                    ListTile(
                      leading: _selectedRestaurant!.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: WebImageHelper.buildImage(
                                _selectedRestaurant!.imageUrl!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.restaurant),
                                ),
                              ),
                            )
                          : Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.restaurant),
                            ),
                      title: Text(_selectedRestaurant!.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_selectedRestaurant!.category != null)
                            Text(_selectedRestaurant!.category!),
                          Text(_getLocationDisplay(_selectedRestaurant!)),
                          Text(
                            _getPriceRangeDisplay(_selectedRestaurant!),
                            style: TextStyle(
                              color: _getPriceRangeColor(_selectedRestaurant!),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              switch (value) {
                                case 'hotpepper':
                                  _launchHotpepperUrl(_selectedRestaurant!.hotpepperUrl);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'hotpepper',
                                child: Row(
                                  children: [
                                    Icon(Icons.link, size: 18),
                                    SizedBox(width: 8),
                                    Text('ホットペッパーで見る'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => setState(() => _selectedRestaurant = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    // 営業時間警告表示
                    ..._buildOperatingHoursWarnings(),
                  ],
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
            
            // 追加店舗選択
            const Text(
              '追加レストラン（候補店舗を増やせます）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            
            if (_additionalRestaurants.isNotEmpty) ...[
              ...(_additionalRestaurants.map((restaurant) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  color: Colors.orange[50],
                  child: Column(
                    children: [
                      ListTile(
                        leading: restaurant.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: WebImageHelper.buildImage(
                                  restaurant.imageUrl!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorWidget: Container(
                                    width: 50,
                                    height: 50,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.restaurant, size: 20),
                                  ),
                                ),
                              )
                            : Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.restaurant, size: 20),
                              ),
                        title: Text(restaurant.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          restaurant.category ?? '',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              onSelected: (value) {
                                switch (value) {
                                  case 'hotpepper':
                                    _launchHotpepperUrl(restaurant.hotpepperUrl);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'hotpepper',
                                  child: Row(
                                    children: [
                                      Icon(Icons.link, size: 16),
                                      SizedBox(width: 6),
                                      Text('ホットペッパー', style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: () => setState(() => _additionalRestaurants.remove(restaurant)),
                              icon: const Icon(Icons.remove_circle, color: Colors.red, size: 18),
                            ),
                          ],
                        ),
                      ),
                      // 追加レストランの営業時間警告
                      ..._buildAdditionalRestaurantWarnings(restaurant),
                    ],
                  ),
                ),
              ))),
            ],
            
            OutlinedButton.icon(
              onPressed: _showAdditionalRestaurantSelection,
              icon: const Icon(Icons.add),
              label: Text(_additionalRestaurants.isEmpty 
                  ? '追加レストランを選択' 
                  : '更に追加（${_additionalRestaurants.length}店舗選択済み）'),
            ),
            
            const SizedBox(height: 24),
            
            // メッセージ入力
            const Text(
              'メッセージ（任意）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'みんなで一緒にお食事しませんか？',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
            
            const SizedBox(height: 32),
            
            // 送信ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSendRequest() && !_isLoading 
                    ? _sendGroupDateRequest 
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'グループデートリクエストを送信',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _selectDate(int index) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date != null) {
      setState(() {
        _selectedDates[index] = date;
      });
    }
  }

  Future<void> _selectTime(int index) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      setState(() {
        _selectedTimes[index] = time;
      });
    }
  }

  void _clearDateTime(int index) {
    setState(() {
      _selectedDates[index] = null;
      _selectedTimes[index] = null;
    });
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
                  itemCount: _restaurants.length,
                  itemBuilder: (context, index) {
                    final restaurant = _restaurants[index];
                    return Card(
                      child: ListTile(
                        leading: restaurant.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: WebImageHelper.buildImage(
                                  restaurant.imageUrl!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorWidget: Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.restaurant),
                                  ),
                                ),
                              )
                            : Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.restaurant),
                              ),
                        title: Text(restaurant.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (restaurant.category != null)
                              Text(restaurant.category!),
                            Text(_getLocationDisplay(restaurant)),
                            Text(
                              _getPriceRangeDisplay(restaurant),
                              style: TextStyle(
                                color: _getPriceRangeColor(restaurant),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedRestaurant = restaurant;
                          });
                          Navigator.pop(context);
                        },
                      ),
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
    
    final availableRestaurants = _restaurants
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
                '日程確定後、みんなで店舗を選びます',
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
                      return Card(
                        child: ListTile(
                          leading: restaurant.imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: WebImageHelper.buildImage(
                                    restaurant.imageUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorWidget: Container(
                                      width: 60,
                                      height: 60,
                                      color: Colors.grey[200],
                                      child: const Icon(Icons.restaurant),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.restaurant),
                                ),
                          title: Text(restaurant.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (restaurant.category != null)
                                Text(restaurant.category!),
                              Text(_getLocationDisplay(restaurant)),
                              Text(
                                _getPriceRangeDisplay(restaurant),
                                style: TextStyle(
                                  color: _getPriceRangeColor(restaurant),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            setState(() {
                              _additionalRestaurants.add(restaurant);
                            });
                            Navigator.pop(context);
                          },
                        ),
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

  Future<void> _sendGroupDateRequest() async {
    if (!_canSendRequest()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 管理者権限をチェック
      final functions = FirebaseFunctions.instance;
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      
      if (currentUserId == null) {
        throw Exception('ユーザーが認証されていません');
      }

      if (!widget.group.admins.contains(currentUserId)) {
        throw Exception('グループデートリクエストの作成は管理者のみ可能です');
      }

      // 身分証明書認証をチェック
      final getUserCallable = functions.httpsCallable('getUserByFirebaseUid');
      final userResult = await getUserCallable.call({'firebaseUid': currentUserId});
      
      if (userResult.data != null && userResult.data['exists'] == true) {
        final isVerified = userResult.data['user']['id_verified'] == true;
        if (!isVerified) {
          throw Exception('グループデートリクエストの作成には身分証明書認証が必要です。設定画面から身分証明書認証を完了してください。');
        }
      } else {
        throw Exception('ユーザー情報を取得できませんでした');
      }

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

      final callable = FirebaseFunctions.instance.httpsCallable('sendGroupDateRequest');
      await callable.call({
        'groupId': widget.group.id,
        'restaurantId': _selectedRestaurant!.id,
        'additionalRestaurantIds': _additionalRestaurants.map((r) => r.id).toList(),
        'message': _messageController.text.trim(),
        'proposedDates': validDateTimes.map((dt) => dt.toIso8601String()).toList(),
        'restaurantOperatingHours': _selectedRestaurant!.operatingHours,
        // 詳細な価格・場所情報を追加
        'restaurantLowPrice': _selectedRestaurant!.lowPrice,
        'restaurantHighPrice': _selectedRestaurant!.highPrice,
        'restaurantNearestStation': _selectedRestaurant!.nearestStation,
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('グループデートリクエストを送信しました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '送信に失敗しました';
        
        if (e.toString().contains('身分証明書認証が必要です')) {
          errorMessage = 'グループデートリクエストの作成には身分証明書認証が必要です。\n設定画面から身分証明書認証を完了してください。';
        } else if (e.toString().contains('管理者のみ可能です')) {
          errorMessage = 'グループデートリクエストの作成は管理者のみ可能です';
        } else if (e.toString().contains('認証されていません')) {
          errorMessage = 'ログインが必要です';
        } else {
          errorMessage = 'エラーが発生しました: ${e.toString().replaceAll('Exception: ', '')}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
} 