import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';

class PhoneAuthPage extends StatefulWidget {
  const PhoneAuthPage({super.key});

  @override
  State<PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  
  bool _isLoading = false;
  bool _codeSent = false;
  String? _verificationId;
  int? _resendToken;
  String _selectedCountryCode = '+81'; // 日本の国番号をデフォルト

  // 国番号リスト
  final List<Map<String, String>> _countryCodes = [
    {'code': '+81', 'country': '日本', 'flag': '🇯🇵'},
    {'code': '+1', 'country': 'アメリカ', 'flag': '🇺🇸'},
    {'code': '+82', 'country': '韓国', 'flag': '🇰🇷'},
    {'code': '+86', 'country': '中国', 'flag': '🇨🇳'},
    {'code': '+44', 'country': 'イギリス', 'flag': '🇬🇧'},
    {'code': '+33', 'country': 'フランス', 'flag': '🇫🇷'},
    {'code': '+49', 'country': 'ドイツ', 'flag': '🇩🇪'},
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _formattedPhoneNumber {
    return '$_selectedCountryCode${_phoneController.text.trim()}';
  }

  Future<void> _sendVerificationCode() async {
    if (_phoneController.text.trim().isEmpty) {
      _showErrorSnackBar('電話番号を入力してください');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await AuthService.signInWithPhoneNumber(
        _formattedPhoneNumber,
        _onVerificationCompleted,
        _onVerificationFailed,
        _onCodeSent,
        _onAutoRetrievalTimeout,
      );
    } catch (e) {
      _showErrorSnackBar('認証コード送信に失敗しました: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onVerificationCompleted(PhoneAuthCredential credential) async {
    try {
      // 自動認証が完了した場合
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      if (mounted) {
        _showSuccessSnackBar('SMS認証が完了しました！');
        
        // 少し待ってからAuthWrapperに状態変化を通知
        await Future.delayed(const Duration(milliseconds: 500));
        
        // SMS認証完了後は、AuthWrapperが自動的に適切な画面に遷移するため、
        // Navigatorを複数回popして認証画面スタック全体をクリアする
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('認証に失敗しました: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onVerificationFailed(FirebaseAuthException e) {
    String errorMessage;
    switch (e.code) {
      case 'invalid-phone-number':
        errorMessage = '無効な電話番号です';
        break;
      case 'too-many-requests':
        errorMessage = '認証試行回数が多すぎます。しばらく待ってから再試行してください';
        break;
      case 'quota-exceeded':
        errorMessage = '認証回数の上限に達しました';
        break;
      default:
        errorMessage = '認証に失敗しました: ${e.message}';
    }
    
    _showErrorSnackBar(errorMessage);
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onCodeSent(String verificationId, int? resendToken) {
    if (mounted) {
      setState(() {
        _codeSent = true;
        _verificationId = verificationId;
        _resendToken = resendToken;
        _isLoading = false;
      });
      
      _showSuccessSnackBar('認証コードを送信しました');
    }
  }

  void _onAutoRetrievalTimeout(String verificationId) {
    // 自動取得がタイムアウトした場合の処理
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().isEmpty) {
      _showErrorSnackBar('認証コードを入力してください');
      return;
    }

    if (_verificationId == null) {
      _showErrorSnackBar('認証IDが無効です');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = await AuthService.verifyPhoneCode(
        _verificationId!,
        _codeController.text.trim(),
      );
      
      
      if (mounted) {
        _showSuccessSnackBar('SMS認証が完了しました！');
        
        // 少し待ってからAuthWrapperに状態変化を通知
        await Future.delayed(const Duration(milliseconds: 500));
        
        // SMS認証完了後は、AuthWrapperが自動的に適切な画面に遷移するため、
        // Navigatorを複数回popして認証画面スタック全体をクリアする
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showErrorSnackBar('認証コードが正しくありません');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await AuthService.signInWithPhoneNumber(
        _formattedPhoneNumber,
        _onVerificationCompleted,
        _onVerificationFailed,
        _onCodeSent,
        _onAutoRetrievalTimeout,
      );
    } catch (e) {
      _showErrorSnackBar('再送信に失敗しました: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS認証'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 説明テキスト
            const Text(
              'SMS認証',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? '送信された認証コードを入力してください'
                  : '電話番号を入力してSMS認証コードを受け取ってください',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 32),
            
            if (!_codeSent) ...[
              // 電話番号入力フェーズ
              const Text(
                '電話番号',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              Row(
                children: [
                  // 国番号選択
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedCountryCode,
                      underline: const SizedBox(),
                      items: _countryCodes.map((country) {
                        return DropdownMenuItem<String>(
                          value: country['code'],
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(country['flag']!),
                              const SizedBox(width: 8),
                              Text(country['code']!),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedCountryCode = value;
                          });
                        }
                      },
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 電話番号入力
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '09012345678',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              Text(
                '例: 090-1234-5678 の場合は 09012345678 と入力',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 認証コード送信ボタン
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendVerificationCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '認証コードを送信',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ] else ...[
              // 認証コード入力フェーズ
              const Text(
                '認証コード',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '123456',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.sms),
                ),
                enabled: !_isLoading,
                maxLength: 6,
              ),
              
              Text(
                '${_formattedPhoneNumber} に送信されたコードを入力してください',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // 認証確認ボタン
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '認証する',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 再送信ボタン
              Center(
                child: TextButton(
                  onPressed: _isLoading ? null : _resendCode,
                  child: const Text(
                    'コードを再送信',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.pink,
                    ),
                  ),
                ),
              ),
              
              // 電話番号変更ボタン
              Center(
                child: TextButton(
                  onPressed: _isLoading ? null : () {
                    setState(() {
                      _codeSent = false;
                      _verificationId = null;
                      _codeController.clear();
                    });
                  },
                  child: const Text(
                    '電話番号を変更',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 32),
            
            // 注意事項
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade600),
                      const SizedBox(width: 8),
                      Text(
                        '注意事項',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• SMSの受信に時間がかかる場合があります\n'
                    '• 認証コードの有効期限は60秒です\n'
                    '• 認証コードが届かない場合は再送信してください',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 