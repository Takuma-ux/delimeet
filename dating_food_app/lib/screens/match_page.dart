import 'package:flutter/material.dart';

class MatchPage extends StatelessWidget {
  const MatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マッチ'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite, size: 64, color: Colors.pink),
            SizedBox(height: 20),
            Text(
              'マッチ',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('ここにマッチした相手一覧が表示されます'),
          ],
        ),
      ),
    );
  }
}

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