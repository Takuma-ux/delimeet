import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'blocked_users_page.dart';
import 'profile_edit_page.dart';
import '../identity_verification_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/notification_service.dart';
import '../services/instagram_service.dart';
import '../services/instagram_auth_service.dart';
import 'auth/instagram_auth_page.dart';
import '../config/app_config.dart';


class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _isInstagramConnected = false;
  String? _instagramUsername;

  @override
  void initState() {
    super.initState();
    _checkInstagramConnection();
  }

  /// Instagram連携状態をチェック（本格版）
  Future<void> _checkInstagramConnection() async {
    try {
      final isConnected = await InstagramAuthService.isAuthenticated();
      final userInfo = await InstagramAuthService.getUserInfo();
      
      if (mounted) {
        setState(() {
          _isInstagramConnected = isConnected;
          _instagramUsername = userInfo['username'];
        });
      }
    } catch (e) {
    }
  }

  /// 地元案内人バッジ情報を読み込み
  Future<Map<String, dynamic>?> _loadLocalGuideBadge() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getLocalGuideBadge');
      final result = await callable.call({});
      return result.data['badge'];
    } catch (e) {
      return null;
    }
  }

  /// バッジアイコンを作成
  Widget _buildBadgeIcon(String badgeLevel) {
    IconData iconData;
    Color color;

    switch (badgeLevel) {
      case 'platinum':
        iconData = Icons.diamond;
        color = Colors.grey[400]!;
        break;
      case 'gold':
        iconData = Icons.star;
        color = Colors.amber;
        break;
      case 'silver':
        iconData = Icons.star_border;
        color = Colors.grey[600]!;
        break;
      default:
        iconData = Icons.circle;
        color = Colors.brown;
    }

    return Icon(iconData, color: color);
  }

  /// バッジレベル名を取得
  String _getBadgeLevelName(String badgeLevel) {
    switch (badgeLevel) {
      case 'platinum':
        return 'プラチナ';
      case 'gold':
        return 'ゴールド';
      case 'silver':
        return 'シルバー';
      default:
        return 'ブロンズ';
    }
  }

  /// バッジ詳細を表示
  void _showBadgeDetails(Map<String, dynamic> badge) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            _buildBadgeIcon(badge['badge_level']),
            const SizedBox(width: 8),
            Text('地元案内人バッジ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('レベル: ${_getBadgeLevelName(badge['badge_level'])}'),
            Text('総得点: ${badge['total_score']}点'),
            const SizedBox(height: 16),
            const Text('得点内訳:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('・レビュー投稿: ${badge['review_points']}点'),
            Text('・参考になった: ${badge['helpful_points']}点'),
            Text('・お気に入り設定: ${badge['favorite_restaurant_points']}点'),
            const SizedBox(height: 16),
            const Text('得点獲得方法:', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('・レビュー投稿: 個人5点/団体主催者10点/団体メンバー5点'),
            const Text('・レビューの参考になった: 3点/件'),
            const Text('・お気に入りレストラン設定: 5点/店舗'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('アカウント'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ユーザー情報表示（Web版では非表示）
            if (!kIsWeb) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ユーザー情報',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('UID: ${user?.uid ?? '未ログイン'}'),
                      Text('メール: ${user?.email ?? '未設定'}'),
                      Text('認証方法: ${_getAuthProviders(user)}'),
                      Text('ログイン日時: ${user?.metadata.lastSignInTime?.toString() ?? '未ログイン'}'),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
            ],
            
            // 設定メニュー
            const Text(
              '設定',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('プロフィール編集'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileEditPage(),
                  ),
                );
              },
            ),
            
            // 地元案内人バッジ表示
            FutureBuilder<Map<String, dynamic>?>(
              future: _loadLocalGuideBadge(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListTile(
                    leading: Icon(Icons.star, color: Colors.amber),
                    title: Text('地元案内人バッジ'),
                    subtitle: Text('読み込み中...'),
                    trailing: CircularProgressIndicator(),
                  );
                }
                
                if (snapshot.hasError) {
                  return ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: const Text('地元案内人バッジ'),
                    subtitle: const Text('読み込みエラー'),
                    trailing: const Icon(Icons.error, color: Colors.red),
                  );
                }
                
                final badge = snapshot.data;
                if (badge == null) {
                  return const ListTile(
                    leading: Icon(Icons.star, color: Colors.amber),
                    title: Text('地元案内人バッジ'),
                    subtitle: Text('バッジ情報がありません'),
                  );
                }
                
                return ListTile(
                  leading: _buildBadgeIcon(badge['badge_level']),
                  title: const Text('地元案内人バッジ'),
                  subtitle: Text('${badge['total_score']}点 - ${_getBadgeLevelName(badge['badge_level'])}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showBadgeDetails(badge);
                  },
                );
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.verified_user, color: Colors.blue),
              title: const Text('身分証明書認証'),
              subtitle: const Text('年齢確認のため必要です'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const IdentityVerificationScreen(),
                  ),
                );
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: const Text('プライバシー設定'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('プライバシー設定機能は後日実装予定です')),
                );
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('お問い合わせ'),
              subtitle: Text(AppConfig.supportEmail),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                _showSupportOptions();
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('ブロックしたユーザー'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BlockedUsersPage(),
                  ),
                );
              },
            ),
            
            // 開発者用テストセクション（Web版では非表示）
            if (!kIsWeb) ...[
              const SizedBox(height: 32),
              
              const Text(
                '開発者用テスト',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'プッシュ通知テスト',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'スリープ状態でもバナー通知が届くかテストできます',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _sendTestNotification('like'),
                              icon: const Icon(Icons.favorite, size: 16),
                              label: const Text('いいね通知'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pink.shade100,
                                foregroundColor: Colors.pink.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _sendTestNotification('match'),
                              icon: const Icon(Icons.favorite_border, size: 16),
                              label: const Text('マッチ通知'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade100,
                                foregroundColor: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _sendTestNotification('message'),
                          icon: const Icon(Icons.message, size: 16),
                          label: const Text('メッセージ通知'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade100,
                            foregroundColor: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _refreshFCMToken,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('FCMトークン更新'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _checkFCMTokenStatus,
                              icon: const Icon(Icons.info, size: 16),
                              label: const Text('トークン確認'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
            ],
            
            const SizedBox(height: 32),
            
            // 退会・復元ボタン（状態に応じて表示切替）
            FutureBuilder<bool>(
              future: _checkAccountStatus(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // ローディング中は何も表示しない
                  return const SizedBox.shrink();
                }
                final isDeactivated = snapshot.hasData && snapshot.data == true;
                return Column(
                  children: [
                    // 退会ボタン（停止中は非表示）
                    if (!isDeactivated)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _handleDeactivateAccount(context);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'アカウントを退会する',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    // 復元ボタン（停止中のみ表示）
                    if (isDeactivated)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _handleReactivateAccount(context);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'アカウントを復元する',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            
            const SizedBox(height: 16),
            
            // ログアウトボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _handleLogout(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'ログアウト',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _getAuthProviders(User? user) {
    if (user == null) return '未ログイン';
    
    final providerData = user.providerData;
    if (providerData.isEmpty) return '匿名';
    
    final providers = providerData.map((info) {
      switch (info.providerId) {
        case 'phone':
          return '電話番号';
        case 'google.com':
          return 'Google';
        case 'apple.com':
          return 'Apple';
        case 'facebook.com':
          return 'Facebook';
        case 'twitter.com':
          return 'Twitter';
        default:
          return info.providerId;
      }
    }).join(', ');
    
    return providers;
  }

  Future<void> _handleLogout(BuildContext context) async {
    // 確認ダイアログを表示
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト確認'),
        content: const Text('本当にログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ログアウト', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      
      // 現在のユーザー情報を取得
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      
      // Google Sign-Inからサインアウト
      try {
        await GoogleSignIn().signOut();
      } catch (e) {
      }
      
      // Firebaseからサインアウト
      await FirebaseAuth.instance.signOut();
      
      // サインアウト確認
      final currentUserAfterSignOut = FirebaseAuth.instance.currentUser;
      
      // SharedPreferencesの全プロフィール設定フラグをクリア（より確実に）
      try {
        final prefs = await SharedPreferences.getInstance();
        
        // 特定のUIDのフラグをクリア
        if (uid != null) {
          final removed = await prefs.remove('profile_setup_completed_$uid');
        }
        
        // 念のため、全てのプロフィール設定フラグをクリア
        final keys = prefs.getKeys();
        int clearedCount = 0;
        for (final key in keys) {
          if (key.startsWith('profile_setup_completed_')) {
            await prefs.remove(key);
            clearedCount++;
          }
        }
      } catch (e) {
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ログアウトしました'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        
        // 強制的にアプリを再起動（AuthWrapperの問題を回避）
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ログアウトエラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// お問い合わせオプションを表示
  void _showSupportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'お問い合わせ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            // メール問い合わせ
            ListTile(
              leading: const Icon(Icons.email, color: Colors.blue),
              title: const Text('メールでお問い合わせ'),
              subtitle: Text(AppConfig.supportEmail),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('メールアプリで ${AppConfig.supportEmail} に送信してください'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            ),
            
            // アプリ情報
            ListTile(
              leading: const Icon(Icons.info, color: Colors.grey),
              title: const Text('アプリ情報'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${AppConfig.appName} v${AppConfig.version}'),
                  Text(AppConfig.appDescription),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            
            // 閉じるボタン
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    );
  }



  /// テスト通知を送信
  Future<void> _sendTestNotification(String type) async {
    try {
      // ローディング表示
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('テスト通知を送信中...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );

      final callable = FirebaseFunctions.instance.httpsCallable('sendTestNotification');
      final result = await callable({
        'notificationType': type,
      });

      if (mounted && result.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${result.data['message']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ テスト通知送信エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// FCMトークンを手動更新
  Future<void> _refreshFCMToken() async {
    try {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('FCMトークンを更新中...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );

      final newToken = await NotificationService().refreshFCMToken();
      
      if (mounted) {
        if (newToken != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ FCMトークン更新完了: ${newToken.substring(0, 20)}...'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ FCMトークン更新失敗'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ FCMトークン更新エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// FCMトークンの状態を確認
  Future<void> _checkFCMTokenStatus() async {
    try {
      if (!mounted) return;
      
      final notificationService = NotificationService();
      final currentToken = notificationService.fcmToken;
      
      String status;
      Color statusColor;
      
      if (currentToken != null) {
        status = '✅ FCMトークン取得済み\n${currentToken.substring(0, 30)}...';
        statusColor = Colors.green;
      } else {
        status = '❌ FCMトークンが取得されていません\n\n考えられる原因：\n• シミュレーターを使用している\n• 通知権限が拒否されている\n• APNs設定に問題がある';
        statusColor = Colors.red;
      }
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('FCMトークン状態'),
            content: Text(status),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
              if (currentToken == null)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _refreshFCMToken();
                  },
                  child: const Text('再取得'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 状態確認エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// アカウントステータスをチェック
  Future<bool> _checkAccountStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final callable = FirebaseFunctions.instance.httpsCallable('getUserProfile');
      final result = await callable.call();

      if (result.data['exists'] == true) {
        // アカウントステータスを確認
        final userData = result.data['user'];
        if (userData != null && userData['deactivated_at'] != null) {
          // deactivated_atが設定されている場合、停止中かどうかをチェック
          final deactivatedAt = DateTime.parse(userData['deactivated_at']);
          final now = DateTime.now();
          return deactivatedAt.isBefore(now); // 停止中ならtrue
        }
        return false; // deactivated_atがnullなら有効
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// アカウント復元処理
  Future<void> _handleReactivateAccount(BuildContext context) async {
    final shouldReactivate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウント復元確認'),
        content: const Text('アカウントを復元しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('復元する', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldReactivate != true) return;

    // ローディング表示
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('復元処理中...'),
            ],
          ),
        ),
      );
    }

    try {
      
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      
      if (uid == null) {
        if (context.mounted) {
          Navigator.pop(context); // ローディングを閉じる
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('アカウントが見つかりませんでした。'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable('reactivateUserAccount');
      final result = await callable({
        'uid': uid,
      });

      if (context.mounted) {
        Navigator.pop(context); // ローディングを閉じる
      }

      if (result.data['success'] == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('アカウントを復元しました。'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {}); // 画面を再構築して「退会する」ボタンを表示
        }
        // 画面遷移はしない
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('復元エラー: ${result.data['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // ローディングを閉じる
      }
      
      if (context.mounted) {
        String errorMessage = '復元エラーが発生しました';
        
        // プラットフォーム共通のエラー情報
        if (e.toString().contains('500')) {
          errorMessage = 'サーバーエラーが発生しました。データベースの設定を確認してください。';
        } else if (e.toString().contains('column "deactivated_at"')) {
          errorMessage = 'データベースの設定が不完全です。管理者にお問い合わせください。';
        } else if (e.toString().contains('internal')) {
          errorMessage = '内部エラーが発生しました。しばらく時間をおいて再度お試しください。';
        } else if (e.toString().contains('network')) {
          errorMessage = 'ネットワークエラーが発生しました。インターネット接続を確認してください。';
        } else if (e.toString().contains('timeout')) {
          errorMessage = 'タイムアウトエラーが発生しました。しばらく時間をおいて再度お試しください。';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '詳細',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('エラー詳細'),
                    content: SingleChildScrollView(
                      child: Text(e.toString()),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  /// アカウント退会処理
  Future<void> _handleDeactivateAccount(BuildContext context) async {
    final shouldDeactivate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウント退会確認'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本当にアカウントを退会しますか？'),
            SizedBox(height: 8),
            Text('• 退会後はいつでも復元可能です'),
            Text('• いいねしたレストランやマッチ履歴は保持されます'),
            Text('• 退会中は他のユーザーからは見えません'),
            Text('• 参加していた全てのグループから退出します'),
            SizedBox(height: 8),
            Text('この操作は取り消せません。', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('退会する', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldDeactivate != true) return;

    // ローディング表示
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('退会処理中...'),
            ],
          ),
        ),
      );
    }

    try {
      
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      
      if (uid == null) {
        if (context.mounted) {
          Navigator.pop(context); // ローディングを閉じる
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('アカウントが見つかりませんでした。'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable('deactivateUserAccount');
      final result = await callable({
        'uid': uid,
      });

      if (context.mounted) {
        Navigator.pop(context); // ローディングを閉じる
      }

      if (result.data['success'] == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('アカウントを退会しました。'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {}); // 画面を再構築して「復元する」ボタンを表示
        }
        // 画面遷移やログアウトはしない
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('退会エラー: ${result.data['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // ローディングを閉じる
      }
      
      if (context.mounted) {
        String errorMessage = '退会エラーが発生しました';
        
        // プラットフォーム共通のエラー情報
        if (e.toString().contains('500')) {
          errorMessage = 'サーバーエラーが発生しました。データベースの設定を確認してください。';
        } else if (e.toString().contains('column "deactivated_at"')) {
          errorMessage = 'データベースの設定が不完全です。管理者にお問い合わせください。';
        } else if (e.toString().contains('internal')) {
          errorMessage = '内部エラーが発生しました。しばらく時間をおいて再度お試しください。';
        } else if (e.toString().contains('network')) {
          errorMessage = 'ネットワークエラーが発生しました。インターネット接続を確認してください。';
        } else if (e.toString().contains('timeout')) {
          errorMessage = 'タイムアウトエラーが発生しました。しばらく時間をおいて再度お試しください。';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '詳細',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('エラー詳細'),
                    content: SingleChildScrollView(
                      child: Text(e.toString()),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  /// 退会後の即時ログアウト処理（確認ダイアログなし）
  Future<void> _forceLogout(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      // UIには何も表示しない
    }
  }

  /// 退会ボタンのonPressedや退会処理関数
  Future<void> _withdrawAndLogout(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (uid == null) {
        throw Exception('ユーザーが見つかりません');
      }
      // Cloud FunctionsのwithdrawAccountをawaitで呼び出す
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('withdrawAccount');
      final result = await callable.call(<String, dynamic>{'uid': uid});
      // 退会APIのレスポンスを待ってからサインアウト
      await _forceLogout(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('退会処理に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

} 