import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_model.dart';
import '../services/group_service.dart';
import '../services/web_image_helper.dart';
import 'group_chat_page.dart';
import 'create_group_page.dart';
import 'group_search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase追加

class GroupListPage extends StatefulWidget {
  const GroupListPage({super.key});

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  final GroupService _groupService = GroupService();

  // キャッシュキー
  static const String _groupCacheKey = 'group_list_cache';
  static const String _groupCacheTimeKey = 'group_list_cache_time';
  static const Duration _cacheValidDuration = Duration(hours: 24);
  List<GroupWithStatus> _groupsWithStatus = [];
  bool _isLoading = true;

  // Supabaseクライアント
  late final SupabaseClient _supabase;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _loadGroupsFromCacheOrSupabase();
  }

  // キャッシュから読み込み、なければSupabaseから取得
  Future<void> _loadGroupsFromCacheOrSupabase() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson = prefs.getString(_groupCacheKey);
    final cacheTime = prefs.getInt(_groupCacheTimeKey);
    bool loadedFromCache = false;
    if (cacheJson != null && cacheTime != null) {
      final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
      if (DateTime.now().difference(cacheDateTime) < _cacheValidDuration) {
        try {
          final List<dynamic> cached = jsonDecode(cacheJson);
          final groups = cached.map((e) => GroupWithStatus.fromJson(e)).toList();
          setState(() {
            _groupsWithStatus = groups;
            _isLoading = false;
          });
          loadedFromCache = true;
        } catch (e) {}
      }
    }
    if (!loadedFromCache) {
      await _loadGroupsFromSupabase();
    }
  }

  // Supabaseから取得後キャッシュ保存
  Future<void> _loadGroupsFromSupabase() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final user = await Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _groupsWithStatus = [];
          _isLoading = false;
        });
        return;
      }
      final userResult = await _supabase
          .from('users')
          .select('id')
          .eq('firebase_uid', user.id)
          .maybeSingle();
      if (userResult == null) {
        setState(() {
          _groupsWithStatus = [];
          _isLoading = false;
        });
        return;
      }
      final userUuid = userResult['id'];
      final memberGroups = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', userUuid);
      final groupIds = memberGroups.map((e) => e['group_id'] as String).toList();
      if (groupIds.isEmpty) {
        setState(() {
          _groupsWithStatus = [];
          _isLoading = false;
        });
        return;
      }
      final groups = await _supabase
          .from('groups')
          .select('id, name, description, imageUrl, createdBy, isPrivate, maxMembers, category, prefecture, nearestStation, tags, createdAt, updatedAt')
          .inFilter('id', groupIds)
          .order('updatedAt', ascending: false);
      final groupList = groups.map<GroupWithStatus>((g) => GroupWithStatus(
        group: Group(
          id: g['id'],
          name: g['name'] ?? '',
          description: g['description'] ?? '',
          imageUrl: g['imageUrl'],
          createdBy: g['createdBy'] ?? '',
          members: [],
          admins: [],
          createdAt: DateTime.tryParse(g['createdAt'] ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(g['updatedAt'] ?? '') ?? DateTime.now(),
          lastMessage: null,
          lastMessageAt: null,
          lastMessageBy: null,
          isPrivate: g['isPrivate'] ?? false,
          maxMembers: g['maxMembers'] ?? 100,
          category: g['category'],
          prefecture: g['prefecture'],
          nearestStation: g['nearestStation'],
          tags: g['tags'] != null ? List<String>.from(g['tags']) : null,
        ),
        status: GroupStatus.member,
        invitationId: null,
      )).toList();
      setState(() {
        _groupsWithStatus = groupList;
        _isLoading = false;
      });
      // キャッシュ保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_groupCacheKey, jsonEncode(groupList.map((g) => g.toJson()).toList()));
      await prefs.setInt(_groupCacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      setState(() {
        _groupsWithStatus = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGroupsToCache(List<GroupWithStatus> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = groups.map((g) => g.toJson()).toList();
    await prefs.setString(_groupCacheKey, jsonEncode(jsonList));
    await prefs.setInt(_groupCacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _loadGroupsFromServer() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final stream = _groupService.getUserGroupsWithInvitations();
      final groups = await stream.first;
      setState(() {
        _groupsWithStatus = groups;
        _isLoading = false;
      });
      await _saveGroupsToCache(groups);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // グループ招待に応答
  Future<void> _respondToInvitation(String invitationId, String groupId, bool accept) async {
    try {
      await _groupService.respondToInvitation(invitationId, groupId, accept);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? 'グループに参加しました！' : '招待を拒否しました'),
            backgroundColor: accept ? Colors.green : Colors.grey,
            duration: const Duration(seconds: 2),
            ),
          );
        }
    } catch (e) {
      if (mounted) {
        // エラーメッセージを詳細化し、nullの場合は汎用メッセージを表示
        String errorMessage;
        if (e.toString().contains('既にグループのメンバーです')) {
          errorMessage = '既にグループに参加済みです';
        } else if (e.toString().contains('null')) {
          errorMessage = accept ? 'グループへの参加処理中にエラーが発生しました' : '招待の拒否処理中にエラーが発生しました';
      } else {
          errorMessage = 'エラーが発生しました: ${e.toString().replaceAll('Exception: ', '')}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // グループ長押しメニュー表示
  void _showGroupLongPressMenu(BuildContext context, GroupWithStatus groupWithStatus) {
    final group = groupWithStatus.group;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      // color: Colors.grey[200], // 背景色を削除（緑色フィルター問題の原因）
                    ),
                    child: group.imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: _buildProperImage(
                              group.imageUrl!,
                              fit: BoxFit.cover,
                              width: 48,
                              height: 48,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey, // エラー時のみ背景色を設定
                                  ),
                                  child: const Icon(Icons.group, size: 28, color: Colors.white),
                                );
                              },
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[200], // 画像がない場合のみ背景色を設定
                            ),
                            child: const Icon(Icons.group, size: 28, color: Colors.grey),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${group.members.length}人のメンバー',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('グループ情報'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupChatPage(group: group),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('グループを削除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteGroup(group);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 🎨 Web対応の画像表示
  Widget _buildProperImage(String imageUrl, {
    required BoxFit fit,
    double? width,
    double? height,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
    Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  }) {
    // Web版ではWebImageHelperを使用してCORS問題を回避
    if (kIsWeb) {
      return WebImageHelper.buildImage(
        imageUrl,
        width: width ?? 200,
        height: height ?? 200,
        fit: fit,
        errorWidget: errorBuilder != null 
            ? errorBuilder(context, Exception('画像読み込み失敗'), StackTrace.current)
            : Container(
                width: width,
                height: height,
                color: Colors.grey[300],
                child: const Icon(Icons.group, size: 28, color: Colors.grey),
              ),
      );
    }
    
    // モバイル版では従来の方法
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorBuilder?.call(context, error, stackTrace) ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.group, size: 28, color: Colors.grey),
            );
      },
    );
  }

  // グループ削除処理
  void _deleteGroup(Group group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('グループを削除'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${group.name}」を完全に削除しますか？'),
            const SizedBox(height: 16),
            const Text(
              '⚠️ この操作は取り消せません',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• 全てのメッセージが削除されます\n'
              '• 全てのメンバーがアクセスできなくなります\n'
              '• グループ画像も削除されます',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performDeleteGroup(group);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // グループ削除実行
  void _performDeleteGroup(Group group) async {
    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('グループを削除中...'),
                ],
              ),
            ),
          ),
        ),
      );

      await _groupService.deleteGroup(group.id);

        if (mounted) {
        // ローディングダイアログを閉じる
        Navigator.pop(context);
        
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
            content: Text('グループを削除しました'),
            backgroundColor: Colors.green,
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        // ローディングダイアログを閉じる
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 古い色空間処理コードを削除（シンプルなImage.networkのみ使用）

  // 最新メッセージの表示部分で
  String getDisplayTextForLatestMessage(Map<String, dynamic> message) {
    if (message['type'] == 'image' || message['message_type'] == 'image') {
      return '画像が送信されました';
    }
    final content = message['content'] ?? '';
    if (content.toString().startsWith('http') && (content.toString().endsWith('.jpg') || content.toString().endsWith('.png'))) {
      return '画像が送信されました';
    }
    return content.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'グループ',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.pink[400],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GroupSearchPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateGroupPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<GroupWithStatus>>(
        stream: _groupService.getUserGroupsWithInvitations(),
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

          final groupsWithStatus = snapshot.data ?? [];

          if (groupsWithStatus.isEmpty) {
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
                          'グループがありません',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '新しいグループを作成してみましょう！',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CreateGroupPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('グループを作成'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink[400],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
            itemCount: groupsWithStatus.length,
                  itemBuilder: (context, index) {
              final groupWithStatus = groupsWithStatus[index];
              return _buildGroupCard(groupWithStatus);
                  },
                );
              },
      ),
    );
  }

  Widget _buildGroupCard(GroupWithStatus groupWithStatus) {
    final group = groupWithStatus.group;
    final isInvited = groupWithStatus.status == GroupStatus.invited;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      color: isInvited ? Colors.orange[50] : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isInvited 
            ? BorderSide(color: Colors.orange[300]!, width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: isInvited ? null : () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupChatPage(group: group),
            ),
          );
        },
        onLongPress: !isInvited && group.admins.contains(_groupService.currentUserId) ? () {
          _showGroupLongPressMenu(context, groupWithStatus);
        } : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 招待バナー（招待されたグループの場合のみ）
              if (isInvited) ...[
                Row(
                  children: [
                    Icon(Icons.group_add, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'グループ招待',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // メインのグループ情報
              Row(
                children: [
                  // グループ画像（親ウィジェットの影響を完全に排除）
                  SizedBox(
                    width: 56,
                    height: 56,
                child: group.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                            child: _buildProperImage(
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
                        : Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[300],
                            ),
                            child: const Icon(Icons.group, size: 28, color: Colors.grey),
                          ),
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
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.members.length}人',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                      ],
                    ),
                  ),
                ],
              ),

              // 招待アクションボタン（招待されたグループの場合のみ）
              if (isInvited) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _respondToInvitation(
                            groupWithStatus.invitationId!,
                            group.id,
                            false, // 拒否
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          side: BorderSide(color: Colors.grey[400]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('拒否'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _respondToInvitation(
                            groupWithStatus.invitationId!,
                            group.id,
                            true, // 参加
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink[400],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('参加'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultGroupIcon() {
    return Icon(
      Icons.group,
      color: Colors.grey[600],
      size: 28,
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return DateFormat('M/d').format(dateTime);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}時間前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分前';
    } else {
      return 'たった今';
    }
  }

} 

// _RawImageProviderクラスを削除（シンプルなImage.networkのみ使用）

