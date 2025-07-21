import 'package:flutter/material.dart';
import '../services/block_service.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      setState(() => _isLoading = true);
      final blockedUsers = await BlockService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = blockedUsers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ブロックリストの取得に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unblockUser(Map<String, dynamic> user) async {
    final userName = user['name'] ?? '名前未設定';
    final userId = user['blocked_id'];

    if (userId == null) return;

    // 確認ダイアログを表示
    final shouldUnblock = await BlockService.showUnblockConfirmDialog(
      context,
      userName,
    );

    if (!shouldUnblock) return;

    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final success = await BlockService.unblockUser(userId);
      
      if (mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${userName}さんのブロックを解除しました'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBlockedUsers(); // リストを再読み込み
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ブロック解除に失敗しました'),
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

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '';
    
    try {
      final DateTime date = DateTime.parse(dateValue.toString()).toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}日前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}時間前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分前';
      } else {
        return 'たった今';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ブロックしたユーザー'),
        backgroundColor: Colors.pink,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.block,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'ブロックしたユーザーはいません',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'ブロックしたユーザーがここに表示されます',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBlockedUsers,
                  child: ListView.builder(
                    itemCount: _blockedUsers.length,
                    itemBuilder: (context, index) {
                      final user = _blockedUsers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: CircleAvatar(
                            radius: 30,
                            backgroundImage: user['image_url'] != null
                                ? NetworkImage(user['image_url'])
                                : null,
                            child: user['image_url'] == null
                                ? const Icon(Icons.person, size: 30)
                                : null,
                          ),
                          title: Text(
                            user['name'] ?? '名前未設定',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${user['age'] ?? '?'}歳 • ${user['gender'] ?? '未設定'}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ブロック日時: ${_formatDate(user['created_at'])}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ブロック状態表示
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.block,
                                      color: Colors.red,
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'ブロック中',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // ブロック解除ボタン
                              ElevatedButton(
                                onPressed: () => _unblockUser(user),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  foregroundColor: Colors.black87,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  minimumSize: Size.zero,
                                ),
                                child: const Text(
                                  '解除',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
} 