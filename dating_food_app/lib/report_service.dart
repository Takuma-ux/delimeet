import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ReportService {
  static const List<Map<String, String>> reportTypes = [
    {
      'value': 'inappropriate_content',
      'label': '不適切なコンテンツ',
      'description': 'プロフィール写真や自己紹介文が不適切'
    },
    {
      'value': 'harassment',
      'label': 'ハラスメント',
      'description': '嫌がらせや迷惑行為'
    },
    {
      'value': 'fake_profile',
      'label': '偽のプロフィール',
      'description': '虚偽の情報や他人の写真を使用'
    },
    {
      'value': 'spam',
      'label': 'スパム',
      'description': '宣伝や勧誘などの迷惑メッセージ'
    },
    {
      'value': 'other',
      'label': 'その他',
      'description': '上記に当てはまらない問題'
    },
  ];

  // 通報ダイアログを表示
  static Future<bool> showReportDialog(
    BuildContext context,
    String reportedUserId,
    String reportedUserName,
  ) async {
    String? selectedReportType;
    String description = '';

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('$reportedUserNameさんを通報'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '通報理由を選択してください',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ...reportTypes.map((type) {
                      return RadioListTile<String>(
                        title: Text(type['label']!),
                        subtitle: Text(
                          type['description']!,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        value: type['value']!,
                        groupValue: selectedReportType,
                        onChanged: (value) {
                          setState(() {
                            selectedReportType = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                    const Text(
                      '詳細（任意）',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: '具体的な内容があれば記入してください',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        description = value;
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚠️ 注意事項',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '• 虚偽の通報は禁止されています\n• 通報内容は運営チームが確認します\n• 悪質な場合は法的措置を取る場合があります',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: selectedReportType != null
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('通報する'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && selectedReportType != null) {
      return await _submitReport(
        context,
        reportedUserId,
        selectedReportType!,
        description.isEmpty ? null : description,
      );
    }

    return false;
  }

  // 通報を送信
  static Future<bool> _submitReport(
    BuildContext context,
    String reportedUserId,
    String reportType,
    String? description,
  ) async {
    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('reportUser');
      
      await callable({
        'reportedUserId': reportedUserId,
        'reportType': reportType,
        'description': description,
      });

      if (context.mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通報を受け付けました。ご協力ありがとうございます。'),
            backgroundColor: Colors.green,
          ),
        );
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // ローディングを閉じる
        
        String errorMessage = '通報の送信に失敗しました';
        if (e.toString().contains('already-exists')) {
          errorMessage = 'このユーザーは既に通報済みです';
        } else if (e.toString().contains('invalid-argument')) {
          errorMessage = '無効な通報内容です';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }

      return false;
    }
  }

  // 通報理由のラベルを取得
  static String getReportTypeLabel(String reportType) {
    final type = reportTypes.firstWhere(
      (type) => type['value'] == reportType,
      orElse: () => {'label': 'その他'},
    );
    return type['label']!;
  }
} 