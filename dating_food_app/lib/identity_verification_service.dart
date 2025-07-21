import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';

/// 身分証明書の種類
enum DocumentType {
  driverLicense('運転免許証'),
  passport('パスポート'),
  myNumberCard('マイナンバーカード'),
  residenceCard('在留カード');

  const DocumentType(this.displayName);
  final String displayName;
}

class IdentityVerificationService {
  static final ImagePicker _picker = ImagePicker();
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// HEIC画像をJPEGに変換
  static Future<File?> convertHeicToJpeg(File heicFile) async {
    try {

      // HEICファイルを読み込み
      final bytes = await heicFile.readAsBytes();
      
      // imageパッケージでデコード（HEIC対応）
      final image = img.decodeImage(bytes);
      if (image == null) {
        return null;
      }
      

      // JPEGエンコード（品質90%）
      final jpegBytes = img.encodeJpg(image, quality: 90);
      
      // 一時ディレクトリに保存
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jpegFile = File('${tempDir.path}/converted_heic_$timestamp.jpg');
      
      await jpegFile.writeAsBytes(jpegBytes);
      
      
      return jpegFile;
    } catch (e) {
      return null;
    }
  }

  /// DocumentTypeをFirebase Functions用の文字列に変換
  static String mapDocumentType(DocumentType type) {
    switch (type) {
      case DocumentType.driverLicense:
        return 'drivers_license';
      case DocumentType.passport:
        return 'passport';
      case DocumentType.myNumberCard:
        return 'mynumber_card';
      case DocumentType.residenceCard:
        return 'residence_card';
    }
  }

  /// 画像を選択
  static Future<dynamic> pickImage({required bool useCamera}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: useCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
        requestFullMetadata: false,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (image != null) {
        if (kIsWeb) {
          // Web: Uint8Listで返す
          final bytes = await image.readAsBytes();
          return bytes;
        } else {
          final File originalFile = File(image.path);
          final String extension = image.path.toLowerCase();
          final bool isHeic = extension.endsWith('.heic') || extension.endsWith('.heif');
          if (isHeic) {
            final convertedFile = await convertHeicToJpeg(originalFile);
            return convertedFile ?? originalFile;
          } else {
            return originalFile;
          }
        }
      }
      return null;
    } catch (e) {
      throw Exception('画像の選択に失敗しました: $e');
    }
  }

  /// 身分証明書をアップロード
  static Future<Map<String, dynamic>> uploadIdentityDocument({
    required DocumentType documentType,
    required dynamic imageFileOrBytes,
  }) async {
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }
      if (kIsWeb) {
        // Web: Uint8Listをbase64エンコードして送信
        final bytes = imageFileOrBytes as Uint8List;
        
        final base64Image = base64Encode(bytes);
        
        // デバッグ情報を出力
        
        final callable = _functions.httpsCallable('uploadIdentityDocument');
        final result = await callable.call({
          'documentType': mapDocumentType(documentType),
          'frontImageBase64': base64Image,
        });
        return Map<String, dynamic>.from(result.data);
      } else {
        // モバイル: Fileでbase64エンコードして送信
        final File imageFile = imageFileOrBytes as File;
        
        final bytes = await imageFile.readAsBytes();
        
        final base64Image = base64Encode(bytes);
        final callable = _functions.httpsCallable('uploadIdentityDocument');
        final result = await callable.call({
          'documentType': mapDocumentType(documentType),
          'frontImageBase64': base64Image,
        });
        return Map<String, dynamic>.from(result.data);
      }
    } catch (e) {
      throw Exception('身分証明書のアップロードに失敗しました: $e');
    }
  }

  /// 認証ステータスを取得
  static Future<Map<String, dynamic>> getVerificationStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      final callable = _functions.httpsCallable('getIdentityVerificationStatus');
      final result = await callable.call();

      if (result.data == null) {
        return {'status': 'not_submitted', 'hasSubmitted': false};
      }

      final data = Map<String, dynamic>.from(result.data);
      
      // Firebase Functions側の戻り値に合わせて変換
      if (data['hasSubmitted'] == false) {
        return {'status': 'not_submitted', 'hasSubmitted': false};
      }
      
      final returnData = {
        'status': data['status'] ?? 'unknown',
        'hasSubmitted': data['hasSubmitted'] ?? false,
        'isVerified': data['isVerified'] ?? false,
        'submitted_at': data['submittedAt'],
        'reviewed_at': data['reviewedAt'],
        'rejection_reason': data['rejectionReason'],
      };
      return returnData;
    } catch (e) {
      // 初回の場合は未申請として扱う
      return {'status': 'not_submitted'};
    }
  }
}

/// 身分証明書認証画面
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({Key? key}) : super(key: key);

  @override
  State<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends State<IdentityVerificationScreen> {
  DocumentType _selectedDocumentType = DocumentType.driverLicense;
  dynamic _selectedImage; // dynamicに変更
  bool _isLoading = false;
  Map<String, dynamic>? _verificationStatus;

  @override
  void initState() {
    super.initState();
    _loadVerificationStatus();
  }

  Future<void> _loadVerificationStatus() async {
    try {
      final status = await IdentityVerificationService.getVerificationStatus();
      
      // 各フィールドの詳細を確認
      status.forEach((key, value) {
      });
      
      if (mounted) {
        setState(() {
          _verificationStatus = status;
        });
      }
    } catch (e) {
      // 初回の場合はエラーを無視
      if (mounted) {
        setState(() {
          _verificationStatus = null;
        });
      }
    }
  }

  Future<void> _pickImage(bool useCamera) async {
    try {
      final image = await IdentityVerificationService.pickImage(useCamera: useCamera);
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('画像選択エラー', e.toString());
      }
    }
  }

  Future<void> _submitVerification() async {
    if (_selectedImage == null) {
      _showErrorDialog('エラー', '身分証明書の画像を選択してください');
      return;
    }

    // デバッグ: 選択された身分証明書タイプを確認

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await IdentityVerificationService.uploadIdentityDocument(
        documentType: _selectedDocumentType,
        imageFileOrBytes: _selectedImage, // 変更
      );


      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? '身分証明書を送信しました。審査をお待ちください。'),
            backgroundColor: result['autoApproved'] == true ? Colors.green : Colors.orange,
          ),
        );
        _loadVerificationStatus();
      }
    } catch (e) {
      _showErrorDialog('送信エラー', e.toString());
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetVerification() async {
    // 確認ダイアログを表示
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('申請をリセット'),
        content: const Text(
          '現在の申請をリセットして、新しい身分証明書画像で再申請しますか？\n\n'
          'この操作は取り消せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('リセット'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase Functionsでリセット処理を実行
      final callable = FirebaseFunctions.instance.httpsCallable('resetIdentityVerification');
      await callable.call();

      // 状態をリセット
      setState(() {
        _verificationStatus = null;
        _selectedImage = null;
      });

      // ステータスを再読み込み
      await _loadVerificationStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('申請をリセットしました。新しい画像で再申請してください。'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('リセットエラー', 'リセット処理に失敗しました: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeString; // パースに失敗した場合は元の文字列を返す
    }
  }

  /// 画像表示（HEIC変換済みかどうかを判定）
  Widget _buildImageWithColorCorrection(dynamic imageData) {
    if (kIsWeb && imageData is Uint8List) {
      return Image.memory(
        imageData,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[300],
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, color: Colors.red, size: 48),
                SizedBox(height: 8),
                Text(
                  '画像の表示に\n問題があります',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          );
        },
      );
    } else if (imageData is File) {
      final String fileName = imageData.path.toLowerCase();
      final bool isConvertedHeic = fileName.contains('converted_heic_') && fileName.endsWith('.jpg');
      final bool isOriginalHeic = fileName.endsWith('.heic') || fileName.endsWith('.heif');
      if (isConvertedHeic) {
        return Stack(
          children: [
            Positioned.fill(
              child: Image.file(
                imageData,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'HEIC→JPEG',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      } else if (isOriginalHeic) {
        return Stack(
          children: [
            Positioned.fill(
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  1.5, -0.6, 0.1, 0.0, 0.0,
                  -0.4, 0.2, 0.0, 0.0, 0.0,
                  0.3, -0.5, 1.6, 0.0, 0.0,
                  0.0, 0.0, 0.0, 1.0, 0.0,
                ]),
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    1.2, 0.0, 0.0, 0.0, 15.0,
                    0.0, 0.3, 0.0, 0.0, -10.0,
                    0.0, 0.0, 1.3, 0.0, 10.0,
                    0.0, 0.0, 0.0, 1.0, 0.0,
                  ]),
                  child: Image.file(
                    imageData,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_fix_high, color: Colors.orange, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'HEIC画像の色補正を適用中\n\n画像は正常にアップロードされます',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.orange),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.blue.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_fix_high,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '色補正済',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  '⚠️ HEIC→JPEG変換に失敗しました\n色補正を適用していますが、JPEG形式での再撮影をお勧めします',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      } else {
        return Image.file(
          imageData,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 8),
                  Text(
                    '画像の表示に\n問題があります',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            );
          },
        );
      }
    } else {
      return const Icon(Icons.error, color: Colors.red);
    }
  }

  Widget _buildStatusCard() {
    if (_verificationStatus == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.assignment, color: Colors.grey),
              SizedBox(width: 8),
              Text('認証ステータス: 未申請'),
            ],
          ),
        ),
      );
    }

    // 型安全な値の取得
    String status = 'unknown';
    String? submittedAt;
    String? rejectionReason;
    String? adminNotes;
    
    try {
      // statusの取得
      final statusValue = _verificationStatus!['status'];
      if (statusValue is String) {
        status = statusValue;
      } else if (statusValue is Map) {
        // statusがMapの場合は、その中身を確認
        status = 'unknown';
      } else {
        status = 'unknown';
      }
      
      // submitted_atの取得
      final submittedAtValue = _verificationStatus!['submitted_at'] ?? _verificationStatus!['submittedAt'];
      if (submittedAtValue is String) {
        submittedAt = submittedAtValue;
      }
      
      // rejection_reasonの取得
      final rejectionReasonValue = _verificationStatus!['rejection_reason'] ?? _verificationStatus!['rejectionReason'];
      if (rejectionReasonValue is String) {
        rejectionReason = rejectionReasonValue;
      }
      
      // admin_notesの取得
      final adminNotesValue = _verificationStatus!['adminNotes'] ?? _verificationStatus!['admin_notes'];
      if (adminNotesValue is String) {
        adminNotes = adminNotesValue;
      }
      
    } catch (e) {
      status = 'unknown';
    }

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusText = '認証完了';
        statusIcon = Icons.verified_user;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusText = '審査中';
        statusIcon = Icons.hourglass_empty;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusText = '認証却下';
        statusIcon = Icons.error;
        break;
      case 'not_submitted':
        statusColor = Colors.grey;
        statusText = '未申請';
        statusIcon = Icons.assignment;
        break;
      default:
        statusColor = Colors.grey;
        statusText = '不明';
        statusIcon = Icons.help;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  '認証ステータス: $statusText',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            if (submittedAt != null && submittedAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('申請日時: ${_formatDateTime(submittedAt)}'),
            ],
            if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rejectionReason.contains('有効期限切れ') 
                  ? '却下理由: 身分証明書の有効期限が切れています'
                  : '却下理由: $rejectionReason',
                style: const TextStyle(color: Colors.red),
              ),
            ],
            // OCRエラーや画像形式エラーの詳細表示
            if (adminNotes != null && adminNotes.isNotEmpty && 
                (adminNotes.contains('OCRエラー') || adminNotes.contains('OCR処理中にエラーが発生しました'))) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red.shade600, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '画像処理エラー',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '送信された画像を正しく処理できませんでした。\n以下をご確認の上、再度お試しください：',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• JPEG、PNG形式の画像をご利用ください\n'
                      '• 画像が鮮明で文字が読み取れることを確認してください\n'
                      '• 身分証明書全体が写っていることを確認してください\n'
                      '• 影や反射がないことを確認してください',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 型安全なステータス取得
    String status = 'not_submitted';
    try {
      final statusValue = _verificationStatus?['status'];
      if (statusValue is String) {
        status = statusValue;
      } else if (statusValue != null) {
      }
    } catch (e) {
    }
    
    final isVerified = status == 'approved';
    final isPending = status == 'pending';
    final isRejected = status == 'rejected';
    
    // 却下理由を確認して自動却下かどうか判定
    final rejectionReasonValue = _verificationStatus?['rejectionReason'] ?? _verificationStatus?['rejection_reason'];
    final rejectionReason = rejectionReasonValue is String ? rejectionReasonValue : null;
    final isAutoRejected = isRejected && (rejectionReason?.contains('身分証明書として認識できません') ?? false);
    final isExpiredRejected = isRejected && (rejectionReason?.contains('有効期限切れ') ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('身分証明書認証'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),

            if (isVerified) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '身分証明書認証が完了しています。\nマッチング機能をご利用いただけます。',
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (isPending) ...[
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hourglass_empty, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '身分証明書を審査中です。\n審査完了までお待ちください。',
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ),
                        ],
                      ),
                      // 審査中でもOCRエラーの場合は詳細を表示
                      if (_verificationStatus != null) ...[
                        Builder(
                          builder: (context) {
                            final adminNotesValue = _verificationStatus!['adminNotes'] ?? _verificationStatus!['admin_notes'];
                            final adminNotes = adminNotesValue is String ? adminNotesValue : null;
                            
                            if (adminNotes != null && adminNotes.isNotEmpty && 
                                (adminNotes.contains('OCRエラー') || adminNotes.contains('OCR処理中にエラーが発生しました'))) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.warning, color: Colors.red.shade600, size: 20),
                                            const SizedBox(width: 8),
                                            Text(
                                              '画像処理エラーが発生しました',
                                              style: TextStyle(
                                                color: Colors.red.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '送信された画像を正しく処理できませんでした。\n別の画像で再度お試しください：',
                                          style: TextStyle(color: Colors.red.shade700),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '• JPEG、PNG形式の画像をご利用ください\n'
                                          '• 画像が鮮明で文字が読み取れることを確認してください\n'
                                          '• 身分証明書全体が写っていることを確認してください\n'
                                          '• 影や反射がないことを確認してください',
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ] else if (isRejected) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isExpiredRejected
                                ? '身分証明書の有効期限が切れています'
                                : isAutoRejected 
                                  ? '身分証明書として認識できませんでした'
                                  : '身分証明書認証が却下されました',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isExpiredRejected
                          ? 'アップロードされた身分証明書の有効期限が切れています。\n有効期限内の身分証明書で再度お試しください。'
                          : isAutoRejected 
                            ? '送信された画像を身分証明書として認識できませんでした。\n以下の点をご確認の上、再度お試しください：'
                            : '身分証明書認証が却下されました。\n新しい画像で再申請してください。',
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                      if (isExpiredRejected) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '期限切れについて：',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• 有効期限内の身分証明書をご用意ください\n'
                                '• 運転免許証、パスポート、マイナンバーカード、在留カードが利用可能です\n'
                                '• 期限の更新手続きが完了している場合は、新しい身分証明書をアップロードしてください',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isAutoRejected) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '確認事項：',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• 運転免許証、パスポート、マイナンバーカード、在留カードのいずれかを使用してください\n'
                                '• 身分証明書全体が写っていることを確認してください\n'
                                '• 文字が鮮明に読み取れることを確認してください\n'
                                '• 影や反射がないことを確認してください\n'
                                '• JPEG、PNG形式の画像をご利用ください',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (rejectionReason != null && rejectionReason.isNotEmpty && !isAutoRejected && !isExpiredRejected) ...[
                        const SizedBox(height: 8),
                        Text(
                          '却下理由: $rejectionReason',
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            if (!isVerified) ...[
              // 既存申請がある場合のリセットボタン
              if (isPending || isRejected) ...[
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.refresh, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Text(
                              '新しい画像で再申請',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '別の身分証明書画像で再度申請することができます。',
                          style: TextStyle(color: Colors.blue),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _resetVerification,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('申請をリセットして再申請'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              const Text(
                '身分証明書の種類',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // 現在選択されている身分証明書タイプを表示
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.pink.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.pink.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.pink.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '選択中: ${_selectedDocumentType.displayName}',
                      style: TextStyle(
                        color: Colors.pink.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: DocumentType.values.map((type) {
                      return RadioListTile<DocumentType>(
                        title: Text(type.displayName),
                        value: type,
                        groupValue: _selectedDocumentType,
                        activeColor: Colors.pink,
                        onChanged: (DocumentType? value) {
                          if (value != null) {
                            setState(() {
                              _selectedDocumentType = value;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                '身分証明書の画像',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_selectedImage != null) ...[
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildImageWithColorCorrection(_selectedImage), // 変更
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickImage(true),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('カメラで撮影'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickImage(false),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('ギャラリーから選択'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '身分証明書を送信',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          '身分証明書認証について',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• スマートフォンでの認証を推奨しております\n'
                      '• 18歳以上の方のみご利用いただけます\n'
                      '• 鮮明で文字が読み取れる画像をアップロードしてください\n'
                      '• 身分証明書全体が写っていることを確認してください\n'
                      '• 審査には1-3営業日かかる場合があります\n',
                      style: TextStyle(color: Colors.blue.shade700),
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
} 