import 'package:flutter/material.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予定'),
        backgroundColor: const Color(0xFFFFEFD5),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event, size: 64, color: const Color(0xFFFFEFD5)),
            SizedBox(height: 20),
            Text(
              '予定',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('ここに予定一覧が表示されます'),
          ],
        ),
      ),
    );
  }
} 