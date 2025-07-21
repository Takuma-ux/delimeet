import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/instagram_auth_service.dart';
import 'profile_setup_page.dart';
import '../home_page.dart';

class InstagramAuthPage extends StatefulWidget {
  final bool isLinking; // true: 既存アカウントとの連携, false: 新規登録

  const InstagramAuthPage({
    super.key,
    this.isLinking = false,
  });

  @override
  State<InstagramAuthPage> createState() => _InstagramAuthPageState();
}

class _InstagramAuthPageState extends State<InstagramAuthPage> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isLinking ? 'Instagram連携' : 'Instagramで登録'),
        backgroundColor: const Color(0xFF833AB4),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Instagramロゴとアイコン
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF833AB4),
                    Color(0xFFFD1D1D),
                    Color(0xFFFCB045),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 50,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // タイトル
            Text(
              widget.isLinking ? 'Instagramアカウントと連携' : 'Instagramで新規登録',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // 開発中メッセージ
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.engineering,
                    size: 48,
                    color: Colors.orange.shade600,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '開発中の機能',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Instagram認証機能は現在開発中です。\n'
                    '正式リリースまでしばらくお待ちください。',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.orange.shade700,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 必要条件の説明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '実装予定機能',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem('Instagram Business API連携'),
                  _buildFeatureItem('投稿の自動共有'),
                  _buildFeatureItem('プロフィール情報の取得'),
                  _buildFeatureItem('投稿コンテンツの管理'),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // エラーメッセージ
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            
            // デバッグ用認証ボタン（開発中）
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _mockInstagramAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bug_report, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'デバッグ用認証（開発中）',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // キャンセルボタン
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              child: const Text(
                'キャンセル',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 注意事項
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule, color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '今後の予定',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Meta Developer Platformでの審査完了後に実装\n'
                    '• Instagram Business/Creator アカウント対応\n'
                    '• OAuth 2.0 認証フローの実装\n'
                    '• 投稿自動化機能の追加',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.blue.shade700, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // デバッグ用のモック認証（開発中）
  Future<void> _mockInstagramAuth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 開発中のシミュレーション
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ この機能は開発中です。他の認証方法をお試しください。'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        
        Navigator.pop(context, false);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'デバッグ認証エラー: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
} 