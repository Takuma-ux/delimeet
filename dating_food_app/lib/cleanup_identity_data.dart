import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // 🚨🚨🚨 危険: 本番環境では絶対に実行しないこと！🚨🚨🚨
  // このスクリプトは全ての本人確認書類を削除します
  
  const bool isDevelopment = true; // 本番リリース時は必ずfalseに変更
  const bool confirmDeletion = false; // 削除を実行する場合のみtrueに変更
  
  if (!isDevelopment) {
    exit(0);
  }
  
  if (!confirmDeletion) {
    exit(0);
  }
  
  
  // 5秒待機
  for (int i = 5; i > 0; i--) {
    await Future.delayed(Duration(seconds: 1));
  }
  
  // Firebase初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    // 1. Firebase Storage内の身分証明書画像を削除
    await cleanupStorageImages();
    
    // 2. データベースのレコードを削除
    await cleanupDatabaseRecords();
    
  } catch (e) {
  }
  
  exit(0);
}

Future<void> cleanupStorageImages() async {
  
  try {
    final storage = FirebaseStorage.instance;
    final ref = storage.ref().child('identity_documents');
    
    // identity_documentsフォルダ内のすべてのファイルを取得
    final listResult = await ref.listAll();
    
    if (listResult.items.isEmpty) {
      return;
    }
    
    
    // 各ファイルを削除
    for (final item in listResult.items) {
      try {
        await item.delete();
      } catch (e) {
      }
    }
    
  } catch (e) {
  }
}

Future<void> cleanupDatabaseRecords() async {
  
  try {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('cleanupIdentityVerificationData');
    
    final result = await callable.call();
  } catch (e) {
  }
} 