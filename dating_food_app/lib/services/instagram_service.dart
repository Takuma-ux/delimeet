import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class InstagramService {
  static const String _instagramConnectedKey = 'instagram_connected';
  static const String _instagramUsernameKey = 'instagram_username';
  static const String _instagramTokenKey = 'instagram_token';

  /// インスタグラムが連携されているかチェック
  static Future<bool> isInstagramConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_instagramConnectedKey) ?? false;
  }

  /// インスタグラムのユーザー名を取得
  static Future<String?> getInstagramUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_instagramUsernameKey);
  }

  /// インスタグラムアプリがインストールされているかチェック
  static Future<bool> isInstagramInstalled() async {
    try {
      // iOSの場合
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final bool canLaunch = await canLaunchUrl(Uri.parse('instagram://'));
        return canLaunch;
      }
      // Androidの場合
      else if (defaultTargetPlatform == TargetPlatform.android) {
        final bool canLaunch = await canLaunchUrl(Uri.parse('instagram://'));
        return canLaunch;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// インスタグラムに連携する
  static Future<bool> connectToInstagram() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // インスタグラムアプリがインストールされているかチェック
      final bool isInstalled = await isInstagramInstalled();
      
      if (isInstalled) {
        // 連携状態を保存
        await prefs.setBool(_instagramConnectedKey, true);
        await prefs.setString(_instagramUsernameKey, 'connected_user'); // 実際のユーザー名に置き換え
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// インスタグラム連携を解除
  static Future<bool> disconnectFromInstagram() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_instagramConnectedKey);
      await prefs.remove(_instagramUsernameKey);
      await prefs.remove(_instagramTokenKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// インスタグラムアプリを開く
  static Future<bool> openInstagramApp() async {
    try {
      final Uri instagramUrl = Uri.parse('instagram://');
      if (await canLaunchUrl(instagramUrl)) {
        await launchUrl(instagramUrl);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 共有テキストを構築
  static String buildShareText({
    required String caption,
    String? restaurantName,
  }) {
    String shareText = caption;
    if (restaurantName != null && restaurantName.isNotEmpty) {
      shareText += '\n\n📍 $restaurantName';
    }
    shareText += '\n\n#dating_food_app';
    return shareText;
  }

  /// クリップボードに投稿内容をコピー
  static Future<void> copyToClipboard({
    required String caption,
    String? restaurantName,
    String? imageUrl,
  }) async {
    try {
      final String shareText = buildShareText(
        caption: caption,
        restaurantName: restaurantName,
      );
      
      String clipboardContent = shareText;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        clipboardContent += '\n\n画像URL: $imageUrl';
      }
      
      await Clipboard.setData(ClipboardData(text: clipboardContent));
    } catch (e) {
    }
  }

  /// キーボードを非表示にする
  static void dismissKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }
} 