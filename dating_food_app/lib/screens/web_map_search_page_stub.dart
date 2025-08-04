// Web版以外のプラットフォーム用のダミーファイル
import 'package:flutter/material.dart';

class WebMapSearchPage extends StatefulWidget {
  const WebMapSearchPage({Key? key}) : super(key: key);

  @override
  State<WebMapSearchPage> createState() => _WebMapSearchPageState();
}

class _WebMapSearchPageState extends State<WebMapSearchPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web版専用'),
        backgroundColor: Colors.orange[400],
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'この機能はWeb版でのみ利用可能です',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
} 