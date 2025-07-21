import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import '../config/instagram_config.dart';

class InstagramAuthService {
  // 設定ファイルから値を取得
  static String get _instagramAppId => InstagramConfig.instagramAppId;
  static String get _instagramAppSecret => InstagramConfig.instagramAppSecret;
  static String get _redirectUri => InstagramConfig.redirectUri;
  
  // ローカルストレージキー
  static const String _accessTokenKey = 'instagram_access_token';
  static const String _refreshTokenKey = 'instagram_refresh_token';
  static const String _userIdKey = 'instagram_user_id';
  static const String _usernameKey = 'instagram_username';
  static const String _expiresAtKey = 'instagram_token_expires_at';
  static const String _connectedAtKey = 'instagram_connected_at';

  /// 設定確認
  static bool get isConfigured => InstagramConfig.isConfigured;
  
  /// 設定確認メッセージ
  static String get configurationMessage => InstagramConfig.configurationMessage;

  /// OAuth状態管理用のランダム文字列生成
  static String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Instagram OAuth認証URLを生成
  static Future<String> generateAuthUrl({
    List<String>? scopes,
  }) async {
    if (!isConfigured) {
      throw Exception('Instagram API設定が未完了です。InstagramConfigを確認してください。');
    }
    
    final state = _generateState();
    final requestScopes = scopes ?? InstagramConfig.scopes;
    
    // CSRF対策のためstateを保存
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('instagram_oauth_state', state);
    
    final params = {
      'client_id': _instagramAppId,
      'redirect_uri': _redirectUri,
      'scope': requestScopes.join(','),
      'response_type': 'code',
      'state': state,
    };
    
    final query = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return 'https://api.instagram.com/oauth/authorize?$query';
  }

  /// 認証コードをアクセストークンに交換
  static Future<Map<String, dynamic>?> exchangeCodeForToken(
    String code,
    String state,
  ) async {
    try {
      if (!isConfigured) {
        throw Exception('Instagram API設定が未完了です。InstagramConfigを確認してください。');
      }
      
      // state検証（CSRF対策）
      final prefs = await SharedPreferences.getInstance();
      final savedState = prefs.getString('instagram_oauth_state');
      
      if (savedState != state) {
        throw Exception('Invalid state parameter');
      }
      
      // 認証コードをアクセストークンに交換
      final response = await http.post(
        Uri.parse('https://api.instagram.com/oauth/access_token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _instagramAppId,
          'client_secret': _instagramAppSecret,
          'grant_type': 'authorization_code',
          'redirect_uri': _redirectUri,
          'code': code,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 短期トークンを長期トークンに交換
        final longLivedToken = await _exchangeForLongLivedToken(data['access_token']);
        
        if (longLivedToken != null) {
          // トークン情報を保存
          await _saveTokenInfo(longLivedToken);
          return longLivedToken;
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 短期トークンを長期トークンに交換
  static Future<Map<String, dynamic>?> _exchangeForLongLivedToken(String shortToken) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://graph.instagram.com/access_token?'
          'grant_type=ig_exchange_token&'
          'client_secret=$_instagramAppSecret&'
          'access_token=$shortToken'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // ユーザー情報も取得
        final userInfo = await _getUserInfo(data['access_token']);
        
        return {
          'access_token': data['access_token'],
          'token_type': data['token_type'] ?? 'Bearer',
          'expires_in': data['expires_in'] ?? 5184000, // 60日
          'user_id': userInfo?['id'],
          'username': userInfo?['username'],
          'account_type': userInfo?['account_type'],
        };
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// ユーザー情報取得
  static Future<Map<String, dynamic>?> _getUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://graph.instagram.com/me?'
          'fields=id,username,account_type&'
          'access_token=$accessToken'
        ),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// トークン情報をローカルに保存
  static Future<void> _saveTokenInfo(Map<String, dynamic> tokenData) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final expiresAt = now.add(Duration(seconds: tokenData['expires_in'] ?? 5184000));
    
    await Future.wait([
      prefs.setString(_accessTokenKey, tokenData['access_token']),
      prefs.setString(_userIdKey, tokenData['user_id'] ?? ''),
      prefs.setString(_usernameKey, tokenData['username'] ?? ''),
      prefs.setString(_expiresAtKey, expiresAt.toIso8601String()),
      prefs.setString(_connectedAtKey, now.toIso8601String()),
    ]);
  }

  /// 現在の認証状態を確認
  static Future<bool> isAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      final expiresAtStr = prefs.getString(_expiresAtKey);
      
      if (accessToken == null || expiresAtStr == null) {
        return false;
      }
      
      final expiresAt = DateTime.parse(expiresAtStr);
      return expiresAt.isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  /// 保存されたアクセストークンを取得
  static Future<String?> getAccessToken() async {
    if (await isAuthenticated()) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_accessTokenKey);
    }
    return null;
  }

  /// Instagram連携ユーザー情報を取得
  static Future<Map<String, String?>> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'user_id': prefs.getString(_userIdKey),
      'username': prefs.getString(_usernameKey),
      'connected_at': prefs.getString(_connectedAtKey),
    };
  }

  /// Instagram認証を解除
  static Future<bool> disconnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_accessTokenKey),
        prefs.remove(_refreshTokenKey),
        prefs.remove(_userIdKey),
        prefs.remove(_usernameKey),
        prefs.remove(_expiresAtKey),
        prefs.remove(_connectedAtKey),
        prefs.remove('instagram_oauth_state'),
      ]);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Firebase Functionsでアカウント連携を処理
  static Future<Map<String, dynamic>?> linkInstagramAccount({
    required String instagramUserId,
    required String instagramUsername,
    required String accessToken,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('linkInstagramAccount');
      final result = await callable.call({
        'instagram_user_id': instagramUserId,
        'instagram_username': instagramUsername,
        'access_token': accessToken,
      });

      return result.data;
    } catch (e) {
      return null;
    }
  }

  /// Instagram認証で新規登録
  static Future<Map<String, dynamic>?> registerWithInstagram({
    required String instagramUserId,
    required String instagramUsername,
    required String accessToken,
    required Map<String, dynamic> profileData,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('registerWithInstagram');
      final result = await callable.call({
        'instagram_user_id': instagramUserId,
        'instagram_username': instagramUsername,
        'access_token': accessToken,
        'profile_data': profileData,
      });

      return result.data;
    } catch (e) {
      return null;
    }
  }

  /// トークンの更新
  static Future<bool> refreshToken() async {
    try {
      final accessToken = await getAccessToken();
      if (accessToken == null) return false;

      final response = await http.get(
        Uri.parse(
          'https://graph.instagram.com/refresh_access_token?'
          'grant_type=ig_refresh_token&'
          'access_token=$accessToken'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveTokenInfo({
          'access_token': data['access_token'],
          'expires_in': data['expires_in'],
        });
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Instagram投稿作成
  static Future<Map<String, dynamic>?> createPost({
    required String imageUrl,
    required String caption,
    String? locationId,
  }) async {
    try {
      final accessToken = await getAccessToken();
      if (accessToken == null) {
        throw Exception('No access token available');
      }

      // 1. メディアコンテナを作成
      final containerResponse = await http.post(
        Uri.parse('https://graph.instagram.com/me/media'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'image_url': imageUrl,
          'caption': caption,
          'access_token': accessToken,
          if (locationId != null) 'location_id': locationId,
        },
      );

      if (containerResponse.statusCode == 200) {
        final containerData = json.decode(containerResponse.body);
        final containerId = containerData['id'];

        // 2. メディアを公開
        final publishResponse = await http.post(
          Uri.parse('https://graph.instagram.com/me/media_publish'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'creation_id': containerId,
            'access_token': accessToken,
          },
        );

        if (publishResponse.statusCode == 200) {
          return json.decode(publishResponse.body);
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 設定確認用のデバッグ情報
  static Map<String, dynamic> getDebugInfo() {
    return {
      'is_configured': isConfigured,
      'configuration_message': configurationMessage,
      'app_id': _instagramAppId,
      'redirect_uri': _redirectUri,
      'scopes': InstagramConfig.scopes,
      'is_development': InstagramConfig.isDevelopment,
    };
  }
} 