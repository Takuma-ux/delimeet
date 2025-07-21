import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase追加
import 'match_detail_page.dart';
import 'profile_view_page.dart';
import '../report_service.dart';
import '../services/block_service.dart';
import '../services/web_image_helper.dart'; // WebImageHelper追加
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// マッチ画面
class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  List<dynamic> _matches = [];
  bool _isLoading = true;
  
  // Supabaseクライアント
  late final SupabaseClient _supabase;
  
  // 画像キャッシュ最適化
  static final Map<String, String> _thumbnailCache = {};
  static const int _maxThumbnailCache = 100;
  
  // キャッシュ機能を追加
  static DateTime? _lastLoadTime;
  static List<dynamic> _cachedMatches = [];
  static const Duration _cacheValidDuration = Duration(hours: 24);
  static const String _cacheKey = 'match_list_cache';
  static const String _cacheTimeKey = 'match_list_cache_time';

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _loadMatchesFromCache();
  }

  // サムネイル画像URLを生成（Firebase Storage最適化）
  String _getThumbnailUrl(String originalUrl, {int width = 200, int height = 200}) {
    if (!originalUrl.contains('firebasestorage.googleapis.com')) {
      return originalUrl; // Firebase Storage以外はそのまま
    }

    // キャッシュチェック
    final cacheKey = '${originalUrl}_${width}x${height}';
    if (_thumbnailCache.containsKey(cacheKey)) {
      return _thumbnailCache[cacheKey]!;
    }

    // Firebase StorageのサムネイルURL生成
    final separator = originalUrl.contains('?') ? '&' : '?';
    final thumbnailUrl = '$originalUrl${separator}w=$width&h=$height&fit=crop';
    
    // キャッシュに保存
    if (_thumbnailCache.length >= _maxThumbnailCache) {
      // 古いキャッシュを削除
      final keysToRemove = _thumbnailCache.keys.take(_maxThumbnailCache ~/ 2).toList();
      for (final key in keysToRemove) {
        _thumbnailCache.remove(key);
      }
    }
    _thumbnailCache[cacheKey] = thumbnailUrl;
    
    return thumbnailUrl;
  }

  // Supabaseから直接マッチデータを取得（高速化）
  Future<List<Map<String, dynamic>>> _getMatchesFromSupabase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No current user found in match list');
        return [];
      }

      // Firebase UIDからUUIDを取得
      final userResult = await _supabase
          .from('users')
          .select('id')
          .eq('firebase_uid', user.uid)
          .maybeSingle();

      if (userResult == null) {
        print('No user found in Supabase for match list');
        return [];
      }

      final userUuid = userResult['id'];
      print('User UUID for match list: $userUuid');

      // マッチデータを取得（インデックス活用）
      final result = await _supabase
          .from('matches')
          .select('''
            id,
            user1_id,
            user2_id,
            restaurant_id,
            created_at,
            status
          ''')
          .or('user1_id.eq.$userUuid,user2_id.eq.$userUuid')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(30);

      print('Matches found: ${result.length}');

      if (result.isEmpty) return [];

      // マッチ相手の詳細情報を取得
      final matchDetails = <Map<String, dynamic>>[];
      for (final match in result) {
        final partnerId = match['user1_id'] == userUuid 
            ? match['user2_id'] 
            : match['user1_id'];

        print('Partner ID: $partnerId');

        // パートナーの詳細情報を取得
        final partnerResult = await _supabase
            .from('users')
            .select('''
              id,
              name,
              image_url,
              age,
              occupation
            ''')
            .eq('id', partnerId)
            .maybeSingle();

        print('Partner result: $partnerResult');

        if (partnerResult != null) {
          // 最新メッセージを取得
          final messageResult = await _supabase
              .from('messages')
              .select('content, created_at')
              .or('sender_id.eq.$userUuid,recipient_id.eq.$userUuid')
              .or('sender_id.eq.$partnerId,recipient_id.eq.$partnerId')
              .order('created_at', ascending: false)
              .limit(1);

          final lastMessage = messageResult.isNotEmpty ? messageResult.first : null;

          matchDetails.add({
            'id': match['id'],
            'partner_id': partnerId,
            'partner_name': partnerResult['name'] ?? '名前未設定',
            'partner_image_url': partnerResult['image_url'],
            'last_message': lastMessage?['content'],
            'last_message_at': lastMessage?['created_at'],
            'created_at': match['created_at'],
            'restaurant_id': match['restaurant_id'],
          });
        }
      }

      print('Match details: ${matchDetails.length}');
      return matchDetails;
    } catch (e) {
      print('Supabase match error: $e');
      return [];
    }
  }

  Future<void> _loadMatchesFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson = prefs.getString(_cacheKey);
    final cacheTime = prefs.getInt(_cacheTimeKey);
    bool loadedFromCache = false;
    if (cacheJson != null && cacheTime != null) {
      final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
      if (DateTime.now().difference(cacheDateTime) < _cacheValidDuration) {
        try {
          final List<dynamic> cached = jsonDecode(cacheJson);
          setState(() {
            _matches = cached;
            _isLoading = false;
          });
          _cachedMatches = cached;
          _lastLoadTime = cacheDateTime;
          loadedFromCache = true;
        } catch (e) {
          // キャッシュが壊れていた場合
        }
      }
    }
    if (!loadedFromCache) {
      // キャッシュがなければサーバーから取得
      await _loadMatches(forceRefresh: true);
    }
  }

  Future<void> _saveMatchesToCache(List<dynamic> matches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(matches));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    _cachedMatches = List.from(matches);
    _lastLoadTime = DateTime.now();
  }

  // サーバーから最新データを取得（リフレッシュや新着時のみ呼ぶ）
  Future<void> _loadMatches({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (!forceRefresh && _cachedMatches.isNotEmpty) {
      setState(() {
        _matches = _cachedMatches;
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      // Supabaseから直接取得（高速化）
      final matches = await _getMatchesFromSupabase();
      
      if (mounted) {
        setState(() {
          _matches = matches;
          _isLoading = false;
        });
        await _saveMatchesToCache(matches);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (_cachedMatches.isNotEmpty) {
          setState(() {
            _matches = _cachedMatches;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('更新ボタンを押してください'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  // 新着メッセージ受信時にこの関数を呼ぶことでリフレッシュ
  Future<void> refreshOnNewMessage() async {
    await _loadMatches(forceRefresh: true);
  }

  // キャッシュが有効かチェック
  bool _isCacheValid() {
    if (_lastLoadTime == null || _cachedMatches.isEmpty) return false;
    return DateTime.now().difference(_lastLoadTime!) < _cacheValidDuration;
  }

  // キャッシュを更新
  void _updateCache(List<dynamic> matches) {
    _lastLoadTime = DateTime.now();
    _cachedMatches = List.from(matches);
  }

  // 最新メッセージの表示テキストを取得（画像URLを隠す）
  String getDisplayTextForLatestMessage(dynamic message) {
    if (message == null || message.toString().isEmpty) {
      return 'まだメッセージがありません';
    }
    
    // メッセージが文字列の場合
    if (message is String) {
      // URLパターンをチェック（画像URLを隠す）
      if (message.contains('firebasestorage.googleapis.com') || 
          message.contains('http') && (message.contains('.jpg') || message.contains('.jpeg') || message.contains('.png'))) {
        return '📷 画像';
      }
      return message;
    }
    
    // メッセージがMapの場合
    if (message is Map<String, dynamic>) {
      final type = message['type'];
      if (type == 'image') {
        return '📷 画像';
      }
      return message['content'] ?? 'メッセージ';
    }
    
    return message.toString();
  }

  // メッセージ削除機能（Supabase直接接続）
  Future<void> _deleteMessages(String matchId, String partnerName) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('メッセージ削除'),
          content: Text('${partnerName}さんとのメッセージ履歴をすべて削除しますか？\n\nこの操作は取り消せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Supabaseから直接メッセージを削除
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      // ユーザーIDを取得
      final userResult = await _supabase
          .from('users')
          .select('id')
          .eq('firebase_uid', user.uid)
          .maybeSingle();

      if (userResult == null) throw Exception('ユーザーが見つかりません');

      final userUuid = userResult['id'];

      // マッチ情報を取得
      final matchResult = await _supabase
          .from('matches')
          .select('user1_id, user2_id')
          .eq('id', matchId)
          .maybeSingle();

      if (matchResult == null) throw Exception('マッチが見つかりません');

      final partnerId = matchResult['user1_id'] == userUuid 
          ? matchResult['user2_id'] 
          : matchResult['user1_id'];

      // メッセージを削除
      await _supabase
          .from('messages')
          .delete()
          .or('sender_id.eq.$userUuid,recipient_id.eq.$userUuid')
          .or('sender_id.eq.$partnerId,recipient_id.eq.$partnerId');

      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${partnerName}さんとのメッセージを削除しました'),
            backgroundColor: Colors.green,
          ),
        );
        
        // マッチ一覧を再読み込み
        _loadMatches(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('メッセージ削除に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 削除されたマッチからメッセージ再開ダイアログ
  void _showRestartMessageDialog(dynamic match, String partnerName, String partnerId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(partnerName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[200],
                ),
                child: match['partner_image_url'] != null
                    ? ClipOval(
                        child: Image.network(
                          match['partner_image_url'],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.person, size: 40, color: Colors.grey),
                        ),
                      )
                    : const Icon(Icons.person, size: 40, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('何をしますか？'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: プロフィール画面に遷移
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('プロフィール画面は今後実装予定です'),
                    backgroundColor: Colors.blue,
                  ),
                );
              },
              child: const Text('プロフィール'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                
                // メッセージがあるかチェック
                final hasMessages = match['last_message'] != null && 
                                  match['last_message'].toString().isNotEmpty;
                
                if (hasMessages) {
                  // 既存の会話がある場合：メッセージ詳細画面に遷移
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatchDetailPage(
                        matchId: match['id'],
                        partnerName: partnerName,
                      ),
                    ),
                  ).then((_) {
                    // 戻ってきたときにマッチ一覧を更新
                    _loadMatches();
                  });
                } else {
                  // メッセージがない場合：新しいメッセージカードを作成
                  _createNewMessageCard(match, partnerName);
                }
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
              ),
              child: const Text('メッセージ'),
            ),
          ],
        );
      },
    );
  }

  // 新しいメッセージカード作成
  void _createNewMessageCard(dynamic match, String partnerName) {
    // 最初のメッセージ送信画面に遷移
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MatchDetailPage(
          matchId: match['id'],
          partnerName: partnerName,
        ),
      ),
    ).then((_) {
      // 戻ってきたときにマッチ一覧を更新
      _loadMatches();
    });
  }

  // 通報機能
  Future<void> _reportUser(String partnerId, String partnerName) async {
    final success = await ReportService.showReportDialog(
      context,
      partnerId,
      partnerName,
    );

    if (success) {
      // 通報成功時は特に何もしない（既にSnackBarで通知済み）
    }
  }

  // ブロック機能
  Future<void> _blockUser(String partnerId, String partnerName) async {
    // 確認ダイアログを表示
    final shouldBlock = await BlockService.showBlockConfirmDialog(
      context,
      partnerName,
    );

    if (!shouldBlock) return;

    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final success = await BlockService.blockUser(partnerId);
      
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${partnerName}さんをブロックしました'),
              backgroundColor: Colors.green,
            ),
          );
          // マッチ一覧を再読み込み（ブロックしたユーザーを除外）
          _loadMatches();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ブロックに失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatLastMessage(dynamic match) {
    final lastMessage = match['last_message'];
    final lastMessageAt = match['last_message_at'];
    
    if (lastMessage == null || lastMessage.isEmpty) {
      return 'まだメッセージがありません';
    }
    
    // 画像URLを隠す処理を適用
    final displayText = getDisplayTextForLatestMessage(lastMessage);
    
    if (lastMessageAt != null) {
      try {
        final DateTime messageTime = DateTime.parse(lastMessageAt).toLocal();
        final DateTime now = DateTime.now();
        final Duration difference = now.difference(messageTime);
        
        String timeStr;
        if (difference.inDays > 0) {
          timeStr = '${difference.inDays}日前';
        } else if (difference.inHours > 0) {
          timeStr = '${difference.inHours}時間前';
        } else if (difference.inMinutes > 0) {
          timeStr = '${difference.inMinutes}分前';
        } else {
          timeStr = 'たった今';
        }
        
        return '$displayText • $timeStr';
      } catch (e) {
        return displayText;
      }
    }
    
    return displayText;
  }

  // マッチアクション選択ダイアログを表示
  void _showMatchActionDialog(BuildContext context, Map<String, dynamic> match, String partnerName, String partnerId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$partnerNameさんとの操作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: const Text('プロフィールを見る'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileViewPage(
                        userId: partnerId,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.green),
                title: const Text('メッセージを送る'),
                onTap: () {
                  Navigator.of(context).pop();
                  // マッチ詳細画面への遷移
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatchDetailPage(
                        matchId: match['id'],
                        partnerName: partnerName,
                      ),
                    ),
                  ).then((_) {
                    _loadMatches();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('ブロックする'),
                onTap: () {
                  Navigator.of(context).pop();
                  _blockUser(partnerId, partnerName);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  // マッチカードを構築する共通メソッド
  Widget _buildMatchCard(dynamic match, bool isLatest) {
    final unreadCount = (match['unread_count'] ?? 0) as int;
    final partnerId = match['partner_id'] ?? '';
    final partnerName = match['partner_name'] ?? '名前未設定';
    
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      elevation: isLatest ? 4 : 2, // 最新メッセージは少し浮かせる
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.grey[200],
              backgroundImage: match['partner_image_url'] != null
                  ? NetworkImage(match['partner_image_url'])
                  : null,
              child: match['partner_image_url'] == null
                  ? const Icon(Icons.person, size: 30, color: Colors.grey)
                  : null,
            ),
            // 未読バッジ
            if (unreadCount > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            // 最新メッセージの場合は特別なバッジ
            if (isLatest)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                partnerName,
                style: TextStyle(
                  fontWeight: unreadCount > 0 
                      ? FontWeight.bold 
                      : FontWeight.normal,
                ),
              ),
            ),
            if (match['restaurant_name'] != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.pink[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.pink, width: 1),
                ),
                child: Text(
                  '🍽️ ${match['restaurant_name']}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.pink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _formatLastMessage(match),
              style: TextStyle(
                color: unreadCount > 0 ? Colors.black : Colors.grey[600],
                fontWeight: unreadCount > 0 
                    ? FontWeight.w500 
                    : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 三点メニューボタン
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'block' && partnerId.isNotEmpty) {
                  await _blockUser(partnerId, partnerName);
                } else if (value == 'delete_messages') {
                  await _deleteMessages(match['id'], partnerName);
                } else if (value == 'report' && partnerId.isNotEmpty) {
                  await _reportUser(partnerId, partnerName);
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'delete_messages',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text('メッセージ削除'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.report, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text('通報'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('ブロック'),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 矢印アイコン
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () {
          // マッチ詳細画面へ遷移（実際の名前を使用）
          final actualPartnerName = match['partner_name'] ?? partnerName ?? '名前未設定';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MatchDetailPage(
                matchId: match['id'],
                partnerName: actualPartnerName,
              ),
            ),
          ).then((_) {
            // 戻ってきたときにマッチ一覧を更新
            _loadMatches();
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マッチ'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadMatches,
            icon: const Icon(Icons.refresh),
            tooltip: '更新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _matches.isEmpty
              ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                      Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 20),
            Text(
                        'まだマッチがありません',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
                      Text(
                        '素敵な人を見つけて、いいねを送ってみましょう！',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMatches,
                  child: Column(
                    children: [
                      // すべてのマッチを上部に横並び表示
                      if (_matches.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'マッチした人',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 120,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _matches.length,
                                  itemBuilder: (context, index) {
                                    final match = _matches[index];
                                    final partnerName = match['partner_name'] ?? '名前未設定';
                                    final partnerId = match['partner_id'] ?? '';
                                    // 24時間以内の新しいマッチかチェック
                                    final createdAt = DateTime.tryParse(match['created_at'] ?? '');
                                    final isNewMatch = createdAt != null && 
                                        DateTime.now().difference(createdAt).inHours < 24;
                                    return Container(
                                      width: 100,
                                      margin: const EdgeInsets.only(right: 12),
                                      child: GestureDetector(
                                        onTap: () {
                                          // 選択肢を表示
                                          _showMatchActionDialog(context, match, partnerName, partnerId);
                                        },
                                        child: Stack(
                                          children: [
                                            Column(
                                              children: [
                                                CircleAvatar(
                                                  radius: 35,
                                                  backgroundColor: Colors.grey[200],
                                                  backgroundImage: match['partner_image_url'] != null
                                                      ? NetworkImage(match['partner_image_url'])
                                                      : null,
                                                  child: match['partner_image_url'] == null
                                                      ? const Icon(Icons.person, size: 35, color: Colors.grey)
                                                      : null,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  partnerName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isNewMatch 
                                                        ? FontWeight.bold 
                                                        : FontWeight.w500,
                                                    color: isNewMatch 
                                                        ? Colors.pink[700] 
                                                        : null,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                            // NEW バッジ
                                            if (isNewMatch)
                                              Positioned(
                                                top: 0,
                                                right: 5,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.pink,
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: const Text(
                                                    'NEW',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(),
                      // すべてのマッチを「メッセージ」として一つのリストで表示
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          border: Border(
                            bottom: BorderSide(color: Colors.blue[200]!, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble, color: Colors.blue[600], size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'メッセージ',
                              style: TextStyle(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // すべてのマッチをリストで表示
                      Expanded(
                        child: _matches.where((match) => 
                          match['last_message'] != null && 
                          match['last_message'].toString().isNotEmpty
                        ).isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                                SizedBox(height: 20),
                                Text(
                                  'まだメッセージがありません',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  '上のマッチした人をタップして\nメッセージを送ってみましょう！',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _matches.where((match) => 
                              match['last_message'] != null && 
                              match['last_message'].toString().isNotEmpty
                            ).length,
                            itemBuilder: (context, index) {
                              final matchesWithMessages = _matches.where((match) => 
                                match['last_message'] != null && 
                                match['last_message'].toString().isNotEmpty
                              ).toList();
                              if (index >= matchesWithMessages.length) return const SizedBox.shrink();
                              final match = matchesWithMessages[index];
                              // 画像UIを「その他のマッチ」と同じ楕円形に統一
                              return _buildMatchCard(match, false);
                            },
                          ),
                      ),
                    ],
                  ),
      ),
    );
  }
} 