import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

class UserImageService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 画像をアップロードしてuser_imagesテーブルに保存
  static Future<Map<String, dynamic>?> uploadImage(
    dynamic imageFile, {
    int? displayOrder,
    bool isPrimary = false,
    String? caption,
    String? restaurantId,
    String? restaurantName,
  }) async {
    try {
      // ユーザー認証状態を確認
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーが認証されていません。再ログインしてください。');
      }
      
      // Web版での認証状態をより厳密にチェック
      if (kIsWeb) {
        try {
          // 認証トークンを明示的に取得して確認
          final token = await user.getIdToken(true);
          if (token == null || token.isEmpty) {
            throw Exception('認証トークンが無効です');
          }
        } catch (e) {
          throw Exception('認証状態が無効です。再ログインしてください。');
        }
      }
      
      // Firebase Storageに画像をアップロード
      String fileName;
      String downloadUrl;
      
      if (kIsWeb) {
        // Web: XFileを使用
        if (imageFile is XFile) {
          // ファイル名を安全な形式に変更
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final originalName = path.basename(imageFile.path);
          final safeName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          fileName = 'user_images/${timestamp}_${safeName}';
          
          final Reference ref = _storage.ref().child(fileName);
          final bytes = await imageFile.readAsBytes();
          
          // Web版では明示的に認証トークンを設定
          final token = await user.getIdToken(true);
          final metadata = SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {
              'userId': user.uid,
              'uploadedAt': DateTime.now().toIso8601String(),
            },
          );
          
          final UploadTask uploadTask = ref.putData(bytes, metadata);
          final TaskSnapshot snapshot = await uploadTask;
          downloadUrl = await snapshot.ref.getDownloadURL();
        } else {
          throw Exception('Web環境ではXFileが必要です');
        }
      } else {
        // モバイル: Fileを使用
        if (imageFile is File) {
          // ファイル名を安全な形式に変更
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final originalName = path.basename(imageFile.path);
          final safeName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          fileName = 'user_images/${timestamp}_${safeName}';
          
          final Reference ref = _storage.ref().child(fileName);
          final UploadTask uploadTask = ref.putFile(imageFile);
          final TaskSnapshot snapshot = await uploadTask;
          downloadUrl = await snapshot.ref.getDownloadURL();
        } else {
          throw Exception('モバイル環境ではFileが必要です');
        }
      }

      // Firebase Functionを呼び出してデータベースに保存
      final HttpsCallable callable = _functions.httpsCallable('uploadUserImage');
      final result = await callable.call({
        'imageUrl': downloadUrl,
        'displayOrder': displayOrder,
        'isPrimary': isPrimary,
        'caption': caption,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
      });

      if (result.data['success'] == true) {
        final imageData = result.data['image'];
        if (imageData != null && imageData is Map) {
          return Map<String, dynamic>.from(imageData);
        } else {
          throw Exception('画像データの形式が正しくありません');
        }
      } else {
        throw Exception('画像の保存に失敗しました');
      }
    } catch (e) {
      
      // 認証関連のエラーの場合はより詳細なメッセージを表示
      if (e.toString().contains('unauthorized') || 
          e.toString().contains('認証') || 
          e.toString().contains('token')) {
        throw Exception('認証エラーが発生しました。再ログインしてください。');
      }
      
      return null;
    }
  }

  /// 画像のメタデータ（キャプション、レストラン情報）を更新
  static Future<bool> updateImageMetadata(
    String imageId, {
    String? caption,
    String? restaurantId,
    String? restaurantName,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('updateUserImageMetadata');
      final result = await callable.call({
        'imageId': imageId,
        'caption': caption,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
      });

      return result.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// 画像を削除
  static Future<bool> deleteImage(String imageId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('deleteUserImage');
      final result = await callable.call({
        'imageId': imageId,
      });

      return result.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// ユーザーの画像一覧を取得
  static Future<List<Map<String, dynamic>>> getUserImages({String? userId}) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('getUserImages');
      final result = await callable.call({
        if (userId != null) 'targetUserId': userId,
      });

      if (result.data['success'] == true) {
        final imagesData = result.data['images'];
        if (imagesData != null && imagesData is List) {
          return imagesData.map((item) {
            if (item is Map) {
              return Map<String, dynamic>.from(item);
            }
            return <String, dynamic>{};
          }).toList();
        }
        return [];
      } else {
        throw Exception('画像の取得に失敗しました');
      }
    } catch (e) {
      return [];
    }
  }

  /// プライマリ画像を設定
  static Future<bool> setPrimaryImage(String imageId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('setPrimaryImage');
      final result = await callable.call({
        'imageId': imageId,
      });

      return result.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// レストラン検索（画像投稿用）
  static Future<List<Map<String, dynamic>>> searchRestaurants(String query) async {
    try {
      
      final HttpsCallable callable = _functions.httpsCallable('searchRestaurants');
      final result = await callable.call({
        'keyword': query,
        'limit': 10,
      });

      
      // 安全な型変換を実装
      List<Map<String, dynamic>> restaurants = [];
      
      if (result.data is Map && result.data['restaurants'] != null) {
        final restaurantsData = result.data['restaurants'];
        if (restaurantsData is List) {
          for (final item in restaurantsData) {
            if (item is Map) {
              final restaurant = <String, dynamic>{};
              item.forEach((key, value) {
                if (key is String) {
                  restaurant[key] = value;
                }
              });
              restaurants.add(restaurant);
            }
          }
        }
      } else if (result.data is List) {
        for (final item in result.data) {
          if (item is Map) {
            final restaurant = <String, dynamic>{};
            item.forEach((key, value) {
              if (key is String) {
                restaurant[key] = value;
              }
            });
            restaurants.add(restaurant);
          }
        }
      }
      
      return restaurants;
    } catch (e) {
      rethrow; // エラーを再スローして呼び出し元で処理
    }
  }

  /// 画像の表示順序を更新（将来の拡張用）
  static Future<bool> updateDisplayOrder(String imageId, int newOrder) async {
    // 現在はFirebase Functionが未実装のため、falseを返す
    // 必要に応じて後で実装
    return false;
  }
} 