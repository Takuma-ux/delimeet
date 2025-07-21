import 'dart:convert';

class Restaurant {
  final String id;
  final String name;
  final String? category;
  final String? prefecture;
  final String? city;
  final String? address;
  final String? nearestStation;
  final String? priceRange;
  final int? lowPrice;
  final int? highPrice;
  final String? imageUrl;
  final String? photoUrl; // ホットペッパーAPI用の別名
  final int? priceLevel; // 価格レベル（1-5）
  final DateTime? likedAt;
  final Map<String, dynamic>? operatingHours; // 営業時間データ
  final String? hotpepperUrl; // ホットペッパーグルメURL
  final double? latitude;
  final double? longitude;

  Restaurant({
    required this.id,
    required this.name,
    this.category,
    this.prefecture,
    this.city,
    this.address,
    this.nearestStation,
    this.priceRange,
    this.lowPrice,
    this.highPrice,
    this.imageUrl,
    this.photoUrl,
    this.priceLevel,
    this.likedAt,
    this.operatingHours,
    this.hotpepperUrl,
    this.latitude,
    this.longitude,
  });

  factory Restaurant.fromMap(Map<String, dynamic> map) {
    // 安全な型変換のヘルパー関数
    String? safeString(dynamic value) {
      if (value == null) return null;
      return value.toString();
    }
    
    int? safeInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse(value.toString());
    }
    
    double? safeDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      return double.tryParse(value.toString());
    }
    
    // 入力データの型チェック
    if (map is! Map<String, dynamic>) {
      throw ArgumentError('Invalid input type for Restaurant.fromMap');
    }
    
    try {
      // operatingHoursの安全な変換
      Map<String, dynamic>? operatingHours;
      final hoursData = map['operating_hours'];
      if (hoursData != null) {
        operatingHours = _safeConvertToMap(hoursData);
      }
      
      // likedAtの安全な変換
      DateTime? likedAt;
      final likedAtData = map['liked_at'];
      if (likedAtData != null) {
        if (likedAtData is DateTime) {
          likedAt = likedAtData;
        } else if (likedAtData is String) {
          likedAt = DateTime.tryParse(likedAtData);
        }
      }
      
      return Restaurant(
        id: safeString(map['id']) ?? '',
        name: safeString(map['name']) ?? '店名未設定',
        category: safeString(map['category']),
        prefecture: safeString(map['prefecture']),
        city: safeString(map['city']),
        address: safeString(map['address']),
        nearestStation: safeString(map['nearest_station']),
        priceRange: safeString(map['price_range']),
        lowPrice: safeInt(map['low_price']),
        highPrice: safeInt(map['high_price']),
        imageUrl: safeString(map['image_url']),
        photoUrl: safeString(map['photo_url']),
        priceLevel: safeInt(map['price_level']),
        likedAt: likedAt,
        operatingHours: operatingHours,
        hotpepperUrl: safeString(map['hotpepper_url']),
        latitude: safeDouble(map['location_latitude']),
        longitude: safeDouble(map['location_longitude']),
      );
    } catch (e, stackTrace) {
      
      // エラーが発生した場合はデフォルト値でRestaurantを作成
      return Restaurant(
        id: map['id']?.toString() ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}',
        name: map['name']?.toString() ?? '店名未設定',
        category: map['category']?.toString(),
        prefecture: map['prefecture']?.toString(),
        city: map['city']?.toString(),
        address: map['address']?.toString(),
        nearestStation: map['nearest_station']?.toString(),
        priceRange: map['price_range']?.toString(),
        lowPrice: null,
        highPrice: null,
        imageUrl: map['image_url']?.toString(),
        photoUrl: map['photo_url']?.toString(),
        priceLevel: null,
        likedAt: null,
        operatingHours: null,
        hotpepperUrl: map['hotpepper_url']?.toString(),
        latitude: null,
        longitude: null,
      );
    }
  }

  // 安全な型変換用のヘルパーメソッド
  static Map<String, dynamic>? _safeConvertToMap(dynamic value) {
    if (value == null) return null;
    
    try {
      if (value is Map<String, dynamic>) {
        return Map<String, dynamic>.from(value);
      } else if (value is Map) {
        // Map<Object?, Object?> から Map<String, dynamic> に変換
        final Map<String, dynamic> result = {};
        
        value.forEach((key, val) {
          try {
            String stringKey;
            if (key is String) {
              stringKey = key;
            } else if (key != null) {
              stringKey = key.toString();
            } else {
              return; // nullキーはスキップ
            }
            
            result[stringKey] = val;
          } catch (e) {
            // エラーが発生したキーはスキップ
          }
        });
        
        return result.isNotEmpty ? result : null;
      } else if (value is String) {
        // JSON文字列の場合はパースを試行
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) {
            return _safeConvertToMap(decoded);
          }
        } catch (e) {
        }
        return null;
      } else {
        // その他の型の場合はnullを返す
        return null;
      }
    } catch (e, stackTrace) {
      return null;
    }
  }

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant.fromMap(json);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'prefecture': prefecture,
      'city': city,
      'address': address,
      'nearest_station': nearestStation,
      'price_range': priceRange,
      'low_price': lowPrice,
      'high_price': highPrice,
      'image_url': imageUrl,
      'photo_url': photoUrl,
      'price_level': priceLevel,
      'liked_at': likedAt?.toIso8601String(),
      'operating_hours': operatingHours,
      'hotpepper_url': hotpepperUrl,
      'location_latitude': latitude,
      'location_longitude': longitude,
    };
  }

  // 表示用の画像URLを取得（imageUrlまたはphotoUrlのどちらかを返す）
  String get displayImageUrl => imageUrl ?? photoUrl ?? '';

  // 価格帯の表示用文字列を取得
  String get displayPriceRange {
    if (priceRange != null && priceRange!.isNotEmpty) {
      return priceRange!;
    }
    if (lowPrice != null || highPrice != null) {
      final low = lowPrice != null ? '¥${lowPrice.toString()}' : '¥0';
      final high = highPrice != null ? '¥${highPrice.toString()}' : '¥?';
      return '$low - $high';
    }
    return '価格未設定';
  }

  // カテゴリの表示用文字列を取得
  String get displayCategory => category ?? 'カテゴリなし';

  // 住所の表示用文字列を取得
  String get displayLocation {
    if (prefecture != null && nearestStation != null) {
      return '$prefecture • $nearestStation';
    }
    return prefecture ?? nearestStation ?? address ?? '場所未設定';
  }

  // 地図機能用のヘルパーメソッド
  bool get hasCoordinates => latitude != null && longitude != null;
  
  // 座標が日本の範囲内かチェック
  bool get isValidJapaneseCoordinates {
    if (!hasCoordinates) return false;
    // 日本の緯度経度範囲をチェック
    // 緯度: 24.0 - 46.0, 経度: 123.0 - 146.0
    return latitude! >= 24.0 && latitude! <= 46.0 && 
           longitude! >= 123.0 && longitude! <= 146.0;
  }

  // 詳細な位置表示（市町村も含む）
  String get detailedLocation {
    List<String> parts = [];
    if (prefecture != null) parts.add(prefecture!);
    if (city != null) parts.add(city!);
    if (nearestStation != null) parts.add('${nearestStation!}駅周辺');
    return parts.isNotEmpty ? parts.join(' ') : '場所未設定';
  }

  Restaurant copyWith({
    String? id,
    String? name,
    String? category,
    String? prefecture,
    String? city,
    String? address,
    String? nearestStation,
    String? priceRange,
    int? lowPrice,
    int? highPrice,
    String? imageUrl,
    String? photoUrl,
    int? priceLevel,
    DateTime? likedAt,
    Map<String, dynamic>? operatingHours,
    String? hotpepperUrl,
    double? latitude,
    double? longitude,
  }) {
    return Restaurant(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      prefecture: prefecture ?? this.prefecture,
      city: city ?? this.city,
      address: address ?? this.address,
      nearestStation: nearestStation ?? this.nearestStation,
      priceRange: priceRange ?? this.priceRange,
      lowPrice: lowPrice ?? this.lowPrice,
      highPrice: highPrice ?? this.highPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      photoUrl: photoUrl ?? this.photoUrl,
      priceLevel: priceLevel ?? this.priceLevel,
      likedAt: likedAt ?? this.likedAt,
      operatingHours: operatingHours ?? this.operatingHours,
      hotpepperUrl: hotpepperUrl ?? this.hotpepperUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Restaurant && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Restaurant(id: $id, name: $name, category: $category, prefecture: $prefecture, coordinates: ${hasCoordinates ? '($latitude, $longitude)' : 'none'})';
  }
} 