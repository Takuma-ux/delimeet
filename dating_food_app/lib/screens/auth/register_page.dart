import 'package:flutter/material.dart';
import 'profile_setup_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../../main.dart'; // グローバルナビゲーションキーをインポート
import 'instagram_auth_page.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新規登録'),
        backgroundColor: const Color(0xFFFFEFD5),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          // デバッグ用：現在の認証状態表示
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: '認証状態をリセット',
                  onPressed: () => _showLogoutConfirmDialog(context),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // デバッグ用：認証状態表示
            StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  final user = snapshot.data!;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚠️ 認証済みユーザーが存在',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Email: ${user.email ?? "未設定"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'UID: ${user.uid}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Verified: ${user.emailVerified}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            
            const Text(
              'アカウント作成方法を\n選択してください',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
            
            const SizedBox(height: 32),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // 電話番号認証
                    _buildAuthMethodButton(
                      context,
                      icon: Icons.phone,
                      title: '電話番号で登録',
                      subtitle: 'SMS認証を使用',
                      onTap: () => _handlePhoneAuth(context),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Apple ID
                    _buildAuthMethodButton(
                      context,
                      icon: Icons.apple,
                      title: 'Apple IDで登録',
                      subtitle: 'Touch ID/Face IDで簡単ログイン',
                      onTap: () => _handleAppleAuth(context),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Google
                    _buildAuthMethodButton(
                      context,
                      icon: Icons.g_mobiledata,
                      title: 'Googleで登録',
                      subtitle: 'Googleアカウントを使用',
                      onTap: () => _handleGoogleAuth(context),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Instagram認証
                    _buildAuthMethodButton(
                      context,
                      icon: Icons.camera_alt,
                      title: 'Instagramで登録',
                      subtitle: 'Instagram Business/Creator account',
                      onTap: () => _handleInstagramAuth(context),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // メールアドレス
                    _buildAuthMethodButton(
                      context,
                      icon: Icons.email,
                      title: 'メールアドレスで登録',
                      subtitle: 'パスワードでログイン',
                      onTap: () => _showEmailAuthDialog(context),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // 注意事項
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '18歳未満の方はご利用いただけません。\n登録により利用規約とプライバシーポリシーに同意したものとみなします。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthMethodButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    return Container(
      width: double.infinity,
      height: 64,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDisabled ? Colors.grey.shade300 : Colors.grey.shade400,
            ),
            borderRadius: BorderRadius.circular(12),
            color: isDisabled ? Colors.grey.shade50 : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDisabled ? Colors.grey.shade300 : const Color(0xFFFDF5E6),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  icon,
                  color: isDisabled ? Colors.grey.shade400 : const Color(0xFFFFEFD5),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDisabled ? Colors.grey.shade400 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDisabled ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isDisabled ? Colors.grey.shade300 : Colors.grey.shade400,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePhoneAuth(BuildContext context) {
    _navigateToProfileSetup(context, 'phone');
  }

  void _handleAppleAuth(BuildContext context) {
    _navigateToProfileSetup(context, 'apple');
  }

  void _handleGoogleAuth(BuildContext context) {
    _navigateToProfileSetup(context, 'google');
  }

  void _showEmailAuthDialog(BuildContext context, {String? errorMessage}) {
    
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メールアドレス認証'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // エラーメッセージがある場合のみ表示
            if (errorMessage != null && errorMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'パスワード（6文字以上）',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            const Text(
              '※アカウント作成後、すぐにログインできます。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => _handleEmailAuth(
              context,
              emailController.text,
              passwordController.text,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFEFD5),
              foregroundColor: Colors.white,
            ),
            child: const Text('登録'),
          ),
        ],
      ),
    );
  }

  void _handleEmailAuth(BuildContext context, String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar(context, 'メールアドレスとパスワードを入力してください', Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnackBar(context, 'パスワードは6文字以上で入力してください', Colors.red);
      return;
    }

    // ローディング状態を管理する変数をメソッド全体で使用
    bool isLoadingShown = false;
    BuildContext? loadingContext; // ローディングダイアログのcontextを保存

    try {
      if (context.mounted) {
        Navigator.pop(context); // ダイアログを閉じる
      }

      
      // ローディング表示
      if (context.mounted) {
        isLoadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            loadingContext = dialogContext; // ローディングダイアログのcontextを保存
            return const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('アカウントを作成中...'),
                ],
              ),
            );
          },
        );
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email,
            password: password,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('認証処理がタイムアウトしました。ネットワーク接続を確認してください。');
            },
          );


      // ユーザー作成成功後、ローディングを閉じる
      if (isLoadingShown && loadingContext != null) {
        try {
          Navigator.of(loadingContext!).pop();
        } catch (e) {
        }
        isLoadingShown = false;
      }

      // メール認証をスキップして直接プロフィール設定に遷移

      if (context.mounted) {
        _showSnackBar(context, '🎉 アカウントが作成されました！プロフィールを設定してください。', Colors.green);
        
        // プロフィール設定画面に直接遷移
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfileSetupPage(authMethod: 'email'),
          ),
        );
      } else {
      }

    } on FirebaseAuthException catch (e) {
      
      // ローディングダイアログを安全に閉じる
      if (isLoadingShown && loadingContext != null) {
        try {
          Navigator.of(loadingContext!).pop();
        } catch (navError) {
          // 最後の手段として、ルートレベルでpopを試行
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (rootError) {
          }
        }
        isLoadingShown = false;
      }
      
      String message = 'エラーが発生しました';
      
      switch (e.code) {
        case 'weak-password':
          message = 'パスワードが弱すぎます。もう少し複雑なパスワードを設定してください。';
          break;
        case 'email-already-in-use':
          message = '登録済みのメールアドレスです';
          
          // グローバルナビゲーションキーを使用してエラーダイアログを表示
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 500), () {
              try {
                final navigatorState = navigatorKey.currentState;
                if (navigatorState != null) {
                  showDialog(
                    context: navigatorState.context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.error, color: Colors.red),
                          SizedBox(width: 8),
                          Text('登録エラー'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error, color: Colors.red.shade600, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '❌ $message',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '以下の方法をお試しください：\n'
                            '• 別のメールアドレスで登録\n'
                            '• 既存のアカウントでログイン\n'
                            '• パスワードを忘れた場合は再設定',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop(); // ダイアログを閉じる
                            // ログイン画面に戻る
                            if (navigatorState.canPop()) {
                              navigatorState.pop();
                            }
                          },
                          child: const Text('ログイン画面へ'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop(); // ダイアログを閉じる
                            // 新規登録画面でメールアドレス入力ダイアログを表示
                            Future.delayed(const Duration(milliseconds: 200), () {
                              if (navigatorState.context.mounted) {
                                _showEmailAuthDialog(navigatorState.context);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFEFD5),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('別のメールで登録'),
                        ),
                      ],
                    ),
                  );
                } else {
                }
              } catch (e) {
              }
            });
          });
          return; // ここで処理終了、下の通常のエラー表示は行わない
        case 'invalid-email':
          message = '無効なメールアドレスです。正しい形式で入力してください。';
          break;
        case 'operation-not-allowed':
          message = 'メール認証が無効化されています。管理者にお問い合わせください。';
          break;
        case 'network-request-failed':
          message = 'ネットワーク接続エラーです。接続を確認してください。';
          break;
        default:
          message = 'Firebase認証エラー: ${e.code} - ${e.message}';
      }
      
      
      // 次のフレームで安全にエラーダイアログ表示
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _showSnackBar(context, message, Colors.red);
        }
      });
    } catch (e) {
      
      // ローディングダイアログを安全に閉じる
      if (isLoadingShown && loadingContext != null) {
        try {
          Navigator.of(loadingContext!).pop();
        } catch (navError) {
          // 最後の手段として、ルートレベルでpopを試行
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (rootError) {
          }
        }
        isLoadingShown = false;
      }
      
      // 次のフレームで安全にエラー表示
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          String errorMessage = '処理でエラーが発生しました: $e';
          _showSnackBar(context, errorMessage, Colors.red);
        }
      });
    }
  }

  void _showEmailVerificationScreen(BuildContext context, String email) {
    showDialog(
      context: context,
      barrierDismissible: false, // 必ず認証完了まで表示
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.mail, color: Colors.green),
            SizedBox(width: 8),
            Text('認証メール送信完了'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🎉 認証メールを送信しました！',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '送信先: $email',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '認証手順:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. メールボックスを確認\n'
              '2. 認証リンクをタップ\n'
              '3. ブラウザで認証完了を確認\n'
              '4. このアプリに戻って「認証確認」をタップ',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '⚠️ メールが届かない場合は迷惑メールフォルダもご確認ください',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                // メール再送信
                await FirebaseAuth.instance.currentUser?.sendEmailVerification();
                
                // 再送信完了メッセージ
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📧 認証メールを再送信しました'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 8),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ メール再送信に失敗しました: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 8),
                    ),
                  );
                }
              }
            },
            child: const Text('メール再送信'),
          ),
          ElevatedButton(
            onPressed: () => _checkEmailVerification(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('認証確認'),
          ),
        ],
      ),
    );
  }

  void _checkEmailVerification(BuildContext context) async {
    try {
      
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('認証状況を確認中...'),
            ],
          ),
        ),
      );

      // ユーザー情報を再読み込み（重要）
      await FirebaseAuth.instance.currentUser?.reload();
      
      // 最新のユーザー情報を取得
      final user = FirebaseAuth.instance.currentUser;

      Navigator.pop(context); // ローディングを閉じる

      if (user != null && user.emailVerified) {
        Navigator.pop(context); // 認証ダイアログを閉じる
        
        // 成功メッセージ表示
        _showSnackBar(context, '🎉 メール認証が完了しました！', Colors.green);
        
        // 少し待ってからプロフィール設定画面に遷移
        await Future.delayed(const Duration(milliseconds: 500));
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfileSetupPage(authMethod: 'email'),
          ),
        );
      } else {
        
        // 詳細な案内メッセージ
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ 認証未完了'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('メール認証がまだ完了していません。'),
                SizedBox(height: 16),
                Text(
                  '✅ メールボックスを確認\n'
                  '✅ 認証リンクをタップ\n'
                  '✅ ブラウザで認証完了を確認\n'
                  '✅ このアプリに戻って再度お試し',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _checkEmailVerification(context);
                },
                child: const Text('再確認'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // ローディングを閉じる
      _showSnackBar(context, '❌ 認証状況の確認に失敗しました: $e', Colors.red);
    }
  }

  void _showSnackBar(BuildContext context, String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Instagram認証は近日対応予定です'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _handleInstagramAuth(BuildContext context) async {
    try {
      // Instagram認証画面に遷移
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const InstagramAuthPage(isLinking: false),
        ),
      );
      
      if (result == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Instagram認証が完了しました！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Instagram認証エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEmailAlreadyInUseDialog(BuildContext context) {
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.orange),
              SizedBox(width: 8),
              Text('メールアドレス重複'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'このメールアドレスは既に使用されています。',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                '・別のメールアドレスで登録\n'
                '・既存のアカウントでログイン\n'
                '・パスワードを忘れた場合は再設定',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // ダイアログを閉じる
                Navigator.pop(context); // 登録画面を閉じてログイン画面に戻る
              },
              child: const Text('ログイン画面へ'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showEmailAuthDialog(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFEFD5),
                foregroundColor: Colors.white,
              ),
              child: const Text('別のメールで登録'),
            ),
          ],
        );
      },
    );
    
  }

  void _navigateToProfileSetup(BuildContext context, String authMethod) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileSetupPage(authMethod: authMethod),
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトの確認'),
        content: const Text('ログアウトして認証状態をリセットしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pop(context);
              _showSnackBar(context, 'ログアウトしました', Colors.green);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFEFD5),
              foregroundColor: Colors.white,
            ),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
  }
} 