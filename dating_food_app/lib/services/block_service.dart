import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class BlockService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// ユーザーをブロックする
  static Future<bool> blockUser(String blockedUserId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('blockUser');
      final result = await callable.call({'blockedUserId': blockedUserId});
      
      return result.data['success'] ?? false;
    } catch (e) {
      throw Exception('ブロックに失敗しました: $e');
    }
  }

  /// ユーザーのブロックを解除する
  static Future<bool> unblockUser(String blockedUserId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('unblockUser');
      final result = await callable.call({'blockedUserId': blockedUserId});
      
      return result.data['success'] ?? false;
    } catch (e) {
      throw Exception('ブロック解除に失敗しました: $e');
    }
  }

  /// ブロック状態を確認する
  static Future<Map<String, bool>> getBlockStatus(String targetUserId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('getBlockStatus');
      final result = await callable.call({'targetUserId': targetUserId});
      
      return {
        'isBlocking': result.data['isBlocking'] ?? false,
        'isBlocked': result.data['isBlocked'] ?? false,
      };
    } catch (e) {
      return {'isBlocking': false, 'isBlocked': false};
    }
  }

  /// ブロックしたユーザーのリストを取得する
  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('getBlockedUsers');
      final result = await callable.call();
      
      // データ構造を確認して適切に処理
      if (result.data != null && result.data is Map) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(result.data);
        if (data.containsKey('blockedUsers')) {
          return List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
        } else {
          // 直接配列が返される場合
          return List<Map<String, dynamic>>.from(result.data ?? []);
        }
      }
      
      return [];
    } catch (e) {
      // エラー時は空のリストを返す（エラーを投げない）
      return [];
    }
  }

  /// ブロック確認ダイアログを表示する
  static Future<bool> showBlockConfirmDialog(
    context, 
    String userName,
  ) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ユーザーをブロック'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${userName}さんをブロックしますか？'),
              const SizedBox(height: 16),
              const Text(
                'ブロックすると：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• お互いのプロフィールが見えなくなります'),
              const Text('• メッセージの送受信ができなくなります'),
              const Text('• 検索結果に表示されなくなります'),
              const Text('• マッチが解除されます'),
              const SizedBox(height: 16),
              const Text(
                '※ ブロックは後から解除できます',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('ブロック'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// ブロック解除確認ダイアログを表示する
  static Future<bool> showUnblockConfirmDialog(
    context, 
    String userName,
  ) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ブロック解除'),
          content: Text('${userName}さんのブロックを解除しますか？\n\n解除すると、再びお互いのプロフィールが見えるようになります。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('解除'),
            ),
          ],
        );
      },
    ) ?? false;
  }
} 