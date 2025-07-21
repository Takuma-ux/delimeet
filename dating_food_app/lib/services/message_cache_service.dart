import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MessageCacheService {
  static const String _cachePrefix = 'message_cache_';
  static const int _maxCacheSize = 50; // 最大キャッシュ件数
  static const Duration _cacheExpiry = Duration(hours: 24); // キャッシュ有効期限

  /// メッセージをキャッシュに保存
  static Future<void> cacheMessages(String matchId, List<dynamic> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$matchId';
      
      final cacheData = {
        'messages': messages,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'matchId': matchId,
      };
      
      await prefs.setString(cacheKey, jsonEncode(cacheData));
      
      // キャッシュサイズ管理
      await _manageCacheSize(prefs);
    } catch (e) {
      // キャッシュエラーは無視（アプリの動作に影響しない）
    }
  }

  /// キャッシュからメッセージを取得
  static Future<List<dynamic>?> getCachedMessages(String matchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$matchId';
      
      final cachedString = prefs.getString(cacheKey);
      if (cachedString == null) return null;
      
      final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;
      final timestamp = cacheData['timestamp'] as int;
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      
      // キャッシュの有効期限チェック
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        await prefs.remove(cacheKey);
        return null;
      }
      
      return List<dynamic>.from(cacheData['messages'] ?? []);
    } catch (e) {
      return null;
    }
  }

  /// 特定のマッチのキャッシュを削除
  static Future<void> clearCache(String matchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$matchId';
      await prefs.remove(cacheKey);
    } catch (e) {
      // エラーは無視
    }
  }

  /// 全キャッシュを削除
  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_cachePrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      // エラーは無視
    }
  }

  /// キャッシュサイズ管理
  static Future<void> _manageCacheSize(SharedPreferences prefs) async {
    try {
      final keys = prefs.getKeys();
      final cacheKeys = keys.where((key) => key.startsWith(_cachePrefix)).toList();
      
      if (cacheKeys.length <= _maxCacheSize) return;
      
      // 古いキャッシュから削除
      final cacheEntries = <MapEntry<String, int>>[];
      
      for (final key in cacheKeys) {
        try {
          final cachedString = prefs.getString(key);
          if (cachedString != null) {
            final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;
            final timestamp = cacheData['timestamp'] as int;
            cacheEntries.add(MapEntry(key, timestamp));
          }
        } catch (e) {
          // 破損したキャッシュは削除
          await prefs.remove(key);
        }
      }
      
      // タイムスタンプでソート（古い順）
      cacheEntries.sort((a, b) => a.value.compareTo(b.value));
      
      // 古いキャッシュを削除
      final deleteCount = cacheEntries.length - _maxCacheSize;
      for (int i = 0; i < deleteCount; i++) {
        await prefs.remove(cacheEntries[i].key);
      }
    } catch (e) {
      // エラーは無視
    }
  }

  /// キャッシュ統計情報を取得
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final cacheKeys = keys.where((key) => key.startsWith(_cachePrefix)).toList();
      
      int totalSize = 0;
      int expiredCount = 0;
      final now = DateTime.now();
      
      for (final key in cacheKeys) {
        try {
          final cachedString = prefs.getString(key);
          if (cachedString != null) {
            totalSize += cachedString.length;
            
            final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;
            final timestamp = cacheData['timestamp'] as int;
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            
            if (now.difference(cacheTime) > _cacheExpiry) {
              expiredCount++;
            }
          }
        } catch (e) {
          // 破損したキャッシュはカウントしない
        }
      }
      
      return {
        'totalEntries': cacheKeys.length,
        'totalSize': totalSize,
        'expiredCount': expiredCount,
        'maxCacheSize': _maxCacheSize,
      };
    } catch (e) {
      return {
        'totalEntries': 0,
        'totalSize': 0,
        'expiredCount': 0,
        'maxCacheSize': _maxCacheSize,
      };
    }
  }
} 