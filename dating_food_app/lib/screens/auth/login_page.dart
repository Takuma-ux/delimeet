import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_page.dart';
import 'phone_auth_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'instagram_auth_page.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  void initState() {
    super.initState();
    // Web版でのGoogle Identity Services初期化は削除
    // 通常のGoogle認証ボタンを使用するため、platformViewRegistryは不要
  }



  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.pink.shade300,
              Colors.pink.shade500,
              Colors.pink.shade700,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            // ConstrainedBoxを削除してシンプルなPaddingに変更
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 上部の余白を追加（画面サイズに依存しない固定値）
                  SizedBox(height: kIsWeb ? 80 : 60),
                  
                  // アプリロゴ・タイトル
                  const Icon(
                    Icons.favorite,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'デリミート',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '素敵な出会いと美味しい食事を',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // SNS認証ボタンエリア
                  _buildAuthMethodsSection(context),
                  
                  const SizedBox(height: 24),
                  
                  // または区切り線
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.white70,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'または',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 新規登録ボタン
                  SizedBox(
                    width: kIsWeb ? 400 : double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        _showEmailRegistrationDialog(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.pink.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 3,
                      ),
                      child: const Text(
                        'メールで新規登録',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // ログインボタン
                  SizedBox(
                    width: kIsWeb ? 400 : double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => _showLoginDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'メールでログイン',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  
                  // Web版では追加の間隔を調整
                  if (kIsWeb) const SizedBox(height: 30),
                  
                  const SizedBox(height: 24),
                  
                  // 利用規約・プライバシーポリシー
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          // TODO: 利用規約を表示
                        },
                        child: const Text(
                          '利用規約',
                          style: TextStyle(
                            color: Colors.white70,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: プライバシーポリシーを表示
                        },
                        child: const Text(
                          'プライバシーポリシー',
                          style: TextStyle(
                            color: Colors.white70,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // 下部の余白を追加（画面サイズに依存しない固定値）
                  SizedBox(height: kIsWeb ? 80 : 60),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthMethodsSection(BuildContext context) {
    return Column(
      children: [
        // Google認証ボタン
        if (kIsWeb)
          SizedBox(
            width: 400,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _signInWithGoogle(context),
              icon: const Icon(Icons.login, color: Colors.black87, size: 20),
              label: const Text(
                'Googleで続ける',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _signInWithGoogle(context),
              icon: const Icon(Icons.login, color: Colors.black87, size: 20),
              label: const Text(
                'Googleで続ける',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
            ),
          ),
        
        const SizedBox(height: 10),
        
        // Apple認証ボタン（iOS版でのみ表示）
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _signInWithApple(context),
              icon: const Icon(Icons.apple, color: Colors.white, size: 20),
              label: const Text(
                'Appleで続ける',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        
        // SMS認証ボタン（モバイル版でのみ表示）
        if (!kIsWeb) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _signInWithPhone(context),
              icon: const Icon(Icons.phone, color: Colors.white, size: 20),
              label: const Text(
                'SMS認証で続ける',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
        
        // 条件付き間隔調整
        if (!kIsWeb) const SizedBox(height: 10),
        
        // LINE認証ボタン（Web版では非表示）
        if (!kIsWeb) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _signInWithLine(context),
            icon: const Icon(Icons.chat, color: Colors.white, size: 20),
            label: const Text(
              'LINEで続ける',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              elevation: 2,
            ),
          ),
        ),
        ],
        
        const SizedBox(height: 12),
        
        // Instagram認証ボタン（Web版では非表示）
        if (!kIsWeb) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _signInWithInstagram(context),
              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
              label: const Text(
                'Instagramで続ける',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF833AB4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
        
        const SizedBox(height: 10),
      ],
    );
  }



  // Google認証
  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      _showLoadingSnackBar(context, 'Googleで認証中...');
      
      final user = await AuthService.signInWithGoogle();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Google認証が完了しました！'),
              backgroundColor: Colors.green,
            ),
          );
          // AuthWrapperが認証状態の変化を検知して自動的に画面遷移する
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google認証がキャンセルされました'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Google認証に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Apple認証
  Future<void> _signInWithApple(BuildContext context) async {
    try {
      _showLoadingSnackBar(context, 'Appleで認証中...');
      
      final user = await AuthService.signInWithApple();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Apple認証が完了しました！'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Apple認証がキャンセルされました'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Apple認証に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // SMS認証
  Future<void> _signInWithPhone(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PhoneAuthPage(),
      ),
    );
    
    // PhoneAuthPageが成功時にpopUntilでルートまで戻るため、
    // ここでは何もしない（結果を受け取らない）
  }

  // LINE認証
  Future<void> _signInWithLine(BuildContext context) async {
    try {
      _showLoadingSnackBar(context, 'LINEで認証中...');
      
      final user = await AuthService.signInWithLine();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 LINE認証が完了しました！'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('LINE認証がキャンセルされました'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ LINE認証に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Instagram認証
  Future<void> _signInWithInstagram(BuildContext context) async {
    try {
      _showLoadingSnackBar(context, 'Instagramで認証中...');
      
      // Instagram認証画面に遷移
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const InstagramAuthPage(isLinking: false),
        ),
      );
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (result == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Instagram認証が完了しました！'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Instagram認証がキャンセルされました'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Instagram認証: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLoadingSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(minutes: 1), // 長めに設定
      ),
    );
  }

  void _showEmailRegistrationDialog(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom - 100,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_add, color: Colors.pink),
                        SizedBox(width: 8),
                        Text(
                          '新規登録',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'メールアドレス',
                          prefixIcon: Icon(Icons.email, color: Colors.pink),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'パスワード（6文字以上）',
                          prefixIcon: Icon(Icons.lock, color: Colors.pink),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '※アカウント作成後、すぐにログインできます。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isLoading)
                      const CircularProgressIndicator()
                    else
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (emailController.text.trim().isEmpty || 
                                    passwordController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('メールアドレスとパスワードを入力してください'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                if (passwordController.text.trim().length < 6) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('パスワードは6文字以上で入力してください'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                setState(() {
                                  isLoading = true;
                                });

                                await _performRegistration(
                                  context,
                                  emailController.text.trim(),
                                  passwordController.text.trim(),
                                );

                                setState(() {
                                  isLoading = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pink,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('登録'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('キャンセル'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom - 100,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.login, color: Colors.pink),
                        SizedBox(width: 8),
                        Text(
                          'ログイン',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'メールアドレス',
                          prefixIcon: Icon(Icons.email, color: Colors.pink),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'パスワード',
                          prefixIcon: Icon(Icons.lock, color: Colors.pink),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isLoading)
                      const CircularProgressIndicator()
                    else
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (emailController.text.trim().isEmpty || 
                                    passwordController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('メールアドレスとパスワードを入力してください'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                setState(() {
                                  isLoading = true;
                                });

                                await _performLogin(
                                  context,
                                  emailController.text.trim(),
                                  passwordController.text.trim(),
                                );

                                setState(() {
                                  isLoading = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pink,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('ログイン'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _showPasswordResetDialog(context);
                            },
                            child: const Text(
                              'パスワードを忘れた方',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('キャンセル'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performRegistration(BuildContext context, String email, String password) async {
    try {

      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );


      if (context.mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 アカウントが作成されました！プロフィールを設定してください。'),
            backgroundColor: Colors.green,
          ),
        );
        
        // AuthWrapperが認証状態の変化を検知して自動的に画面遷移する
      }

    } on FirebaseAuthException catch (e) {

      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'パスワードが弱すぎます。もう少し複雑なパスワードを設定してください。';
          break;
        case 'email-already-in-use':
          errorMessage = 'このメールアドレスは既に使用されています。';
          break;
        case 'invalid-email':
          errorMessage = 'メールアドレスの形式が正しくありません。';
          break;
        case 'operation-not-allowed':
          errorMessage = 'メール認証が無効化されています。管理者にお問い合わせください。';
          break;
        case 'network-request-failed':
          errorMessage = 'ネットワーク接続エラーです。接続を確認してください。';
          break;
        default:
          errorMessage = '新規登録に失敗しました: ${e.message}';
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 予期しないエラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPasswordResetDialog(BuildContext context) {
    final emailController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom - 100,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_reset, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'パスワードリセット',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  const Text(
                    'パスワードリセット用のメールを送信します。\nメールアドレスを入力してください。',
                    style: TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'メールアドレス',
                        prefixIcon: Icon(Icons.email, color: Colors.blue),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📧 リセット手順:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1. メールボックスを確認\n'
                          '2. リセットリンクをクリック\n'
                          '3. 新しいパスワードを設定\n'
                          '4. 新しいパスワードでログイン',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isLoading)
                    const CircularProgressIndicator()
                  else
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (emailController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('メールアドレスを入力してください'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              setState(() {
                                isLoading = true;
                              });

                              await _performPasswordReset(
                                context,
                                emailController.text.trim(),
                              );

                              setState(() {
                                isLoading = false;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('リセットメール送信'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text('キャンセル'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performPasswordReset(BuildContext context, String email) async {
    try {

      // Supabaseのusersテーブルでメールアドレスの登録状況を確認
      
      bool isRegistered = false;
      
      try {
        final functions = FirebaseFunctions.instance;
        final callable = functions.httpsCallable('checkEmailRegistration');
        
        final result = await callable.call({'email': email});
        isRegistered = result.data['isRegistered'] as bool;
        
      } catch (e) {
        // エラーの場合は、Firebase Authの標準動作に任せる（セキュリティ重視）
      }

      if (!isRegistered) {
        // 未登録メールアドレスの場合
        
        if (context.mounted) {
          Navigator.pop(context); // ダイアログを閉じる
          
          // 未登録メールアドレス用のダイアログを表示
          _showUnregisteredEmailDialog(context, email);
        }
        return;
      }

      // 登録済みメールアドレスの場合、パスワードリセットメールを送信
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);


      if (context.mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        
        // 成功ダイアログを表示
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('送信完了'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_read,
                        size: 48,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '📧 パスワードリセットメールを送信しました！',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '送信先: $email',
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'メールボックスを確認し、リセットリンクをクリックして新しいパスワードを設定してください。',
                  style: TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '💡 メールが届かない場合は、迷惑メールフォルダもご確認ください。',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('確認'),
              ),
            ],
          ),
        );
      }

    } on FirebaseAuthException catch (e) {

      if (e.code == 'user-not-found') {
        // 未登録メールアドレスの場合、専用ダイアログを表示
        
        if (context.mounted) {
          Navigator.pop(context); // ダイアログを閉じる
          _showUnregisteredEmailDialog(context, email);
        }
        return;
      }

      // その他のエラーの場合
      String errorMessage;
      switch (e.code) {
        case 'invalid-email':
          errorMessage = 'メールアドレスの形式が正しくありません。';
          break;
        case 'too-many-requests':
          errorMessage = 'リセット要求が多すぎます。しばらく待ってから再試行してください。';
          break;
        default:
          errorMessage = 'パスワードリセットメールの送信に失敗しました: ${e.message}';
      }

      if (context.mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      
      if (context.mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 予期しないエラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _performLogin(BuildContext context, String email, String password) async {
    try {

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );


      if (context.mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        
        // AuthWrapperが認証状態の変化を検知して自動的に画面遷移する
      }

    } on FirebaseAuthException catch (e) {

      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'このメールアドレスは登録されていません';
          break;
        case 'wrong-password':
          errorMessage = 'パスワードが間違っています';
          break;
        case 'invalid-email':
          errorMessage = 'メールアドレスの形式が正しくありません';
          break;
        case 'user-disabled':
          errorMessage = 'アカウントが無効化されています';
          break;
        case 'too-many-requests':
          errorMessage = 'ログイン試行回数が多すぎます。しばらく待ってから再試行してください';
          break;
        case 'invalid-credential':
          errorMessage = 'メールアドレスまたはパスワードに誤りがあります';
          break;
        default:
          errorMessage = 'ログインに失敗しました: ${e.message}';
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 予期しないエラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUnregisteredEmailDialog(BuildContext context, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('未登録メールアドレス'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.person_off,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ このメールアドレスは登録されていません',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'メールアドレス: $email',
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '以下の方法をお試しください：\n\n'
              '• 正しいメールアドレスを入力\n'
              '• 新規アカウントを作成\n'
              '• 別の認証方法でログイン',
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPasswordResetDialog(context); // リセットダイアログに戻る
            },
            child: const Text('再入力'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showEmailRegistrationDialog(context); // 新規登録ダイアログを表示
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
            ),
            child: const Text('新規登録'),
          ),
        ],
      ),
    );
  }
} 