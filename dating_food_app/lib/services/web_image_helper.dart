import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Web版でのCORS問題を解決するための画像プロキシヘルパー
class WebImageHelper {

  // 画像キャッシュ（Web版専用）
  static final Map<String, MemoryImage> _imageCache = {};
  static const int _maxCacheSize = 50; // 最大キャッシュ数

  /// キャッシュをクリア
  static void clearCache() {
    _imageCache.clear();
  }

  /// キャッシュサイズを管理
  static void _manageCacheSize() {
    if (_imageCache.length > _maxCacheSize) {
      // 古いキャッシュを半分削除
      final keysToRemove = _imageCache.keys.take(_imageCache.length ~/ 2).toList();
      for (final key in keysToRemove) {
        _imageCache.remove(key);
      }
    }
  }

  /// 統一的な画像取得（Web版ではプロキシ、モバイルではキャッシュ付き直接読み込み）
  static Future<MemoryImage?> getImageViaProxy(String imageUrl) async {
    // キャッシュチェック（全プラットフォームで使用）
    if (_imageCache.containsKey(imageUrl)) {
      return _imageCache[imageUrl];
    }

    if (kIsWeb) {
      // Web版の処理（既存のまま）
      // Firebase Storageの画像は直接読み込み
      if (imageUrl.contains('firebasestorage.googleapis.com')) {
        try {
          final response = await http.get(Uri.parse(imageUrl)).timeout(
            const Duration(seconds: 10),
          );
          
          if (response.statusCode == 200) {
            final bytes = response.bodyBytes;
            final memoryImage = MemoryImage(bytes);
            _imageCache[imageUrl] = memoryImage; // キャッシュに保存
            _manageCacheSize(); // キャッシュサイズ管理
            return memoryImage;
          } else {
            return null;
          }
        } catch (e) {
          return null;
        }
      }

      // HotPepperの画像のみプロキシ経由（リトライ最小限）
      final isHotPepperImage = imageUrl.contains('hotp.jp') || imageUrl.contains('hotpepper.jp');
      final maxRetries = 1; // リトライ回数を削減
      
      for (int retryCount = 0; retryCount <= maxRetries; retryCount++) {
        try {
          // Firebase Functions のHTTPエンドポイントを直接呼び出し
          const functionsBaseUrl = 'https://us-central1-dating-food-apps.cloudfunctions.net';
          final uri = Uri.parse('$functionsBaseUrl/getImageProxy');
          
          final requestBody = jsonEncode({
            'imageUrl': imageUrl,
          });
          
          final response = await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBody,
          ).timeout(
            Duration(seconds: isHotPepperImage ? 12 : 8), // タイムアウトを短縮
            onTimeout: () {
              throw TimeoutException('リクエストタイムアウト');
            },
          );
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            
            if (data['success'] == true && data['imageData'] != null) {
              final String base64Data = data['imageData'];
              final Uint8List bytes = base64Decode(base64Data);
              final memoryImage = MemoryImage(bytes);
              _imageCache[imageUrl] = memoryImage; // キャッシュに保存
              _manageCacheSize(); // キャッシュサイズ管理
              return memoryImage;
            } else {
              return null;
            }
          } else {
            return null;
          }
        } on TimeoutException catch (e) {
          if (retryCount < maxRetries) {
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          return null;
        } catch (e) {
          return null;
        }
      }
    } else {
      // モバイル版（iOS/Android）での画像キャッシュ
      try {
        final response = await http.get(Uri.parse(imageUrl)).timeout(
          const Duration(seconds: 8),
        );
        
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          final memoryImage = MemoryImage(bytes);
          _imageCache[imageUrl] = memoryImage; // キャッシュに保存
          _manageCacheSize(); // キャッシュサイズ管理
          return memoryImage;
        } else {
          return null;
        }
      } catch (e) {
        return null;
      }
    }
    
    return null;
  }

  /// 統一的な画像ウィジェット作成（Web版ではプロキシ、モバイルでは直接読み込み）
  static Widget buildImage(
    String imageUrl, {
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    BorderRadius? borderRadius,
  }) {
    // デフォルトのプレースホルダーとエラーウィジェット
    final defaultPlaceholder = placeholder ?? Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

    final defaultErrorWidget = errorWidget ?? Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant, size: 30, color: Colors.grey),
          SizedBox(height: 4),
          Text(
            '画像読み込み\n失敗',
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    Widget imageWidget;

    if (kIsWeb) {
      // Web版：プロキシ経由で画像取得
      imageWidget = FutureBuilder<MemoryImage?>(
        future: getImageViaProxy(imageUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return defaultPlaceholder;
          } else if (snapshot.hasData && snapshot.data != null) {
            return Image(
              image: snapshot.data!,
              width: width,
              height: height,
              fit: fit,
            );
          } else {
            return defaultErrorWidget;
          }
        },
      );
    } else {
      // モバイル版：直接ネットワーク画像読み込み
      imageWidget = Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return defaultPlaceholder;
        },
        errorBuilder: (context, error, stackTrace) {
          return defaultErrorWidget;
        },
      );
    }

    // BorderRadiusが指定されている場合はClipRRectで包む
    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  /// 円形画像ウィジェット（プロフィール画像等に使用）
  static Widget buildCircularImage(
    String imageUrl, {
    required double size,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return ClipOval(
      child: buildImage(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: placeholder,
        errorWidget: errorWidget,
      ),
    );
  }

  /// レストランカード用の画像ウィジェット
  static Widget buildRestaurantImage(
    String? imageUrl, {
    required double width,
    required double height,
    BorderRadius? borderRadius,
  }) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
      );
    }

    return buildImage(
      imageUrl,
      width: width,
      height: height,
      borderRadius: borderRadius,
      errorWidget: Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: const Icon(Icons.restaurant, size: 30, color: Colors.grey),
      ),
    );
  }

  /// ユーザープロフィール用の画像ウィジェット
  static Widget buildProfileImage(
    String? imageUrl, {
    required double size,
    bool isCircular = true,
  }) {
    final Widget errorWidget = Container(
      width: size,
      height: size,
      color: Colors.grey[200],
      child: Icon(
        Icons.person,
        size: size * 0.6,
        color: Colors.grey[600],
      ),
    );

    if (imageUrl == null || imageUrl.isEmpty) {
      return isCircular ? ClipOval(child: errorWidget) : errorWidget;
    }

    if (isCircular) {
      return buildCircularImage(
        imageUrl,
        size: size,
        errorWidget: errorWidget,
      );
    } else {
      return buildImage(
        imageUrl,
        width: size,
        height: size,
        errorWidget: errorWidget,
      );
    }
  }
} 