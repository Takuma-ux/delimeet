import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AuthService {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Web版でのGoogle Sign-In設定
    clientId: kIsWeb ? '954695208342-9gs0u8q541qkks09fkl6q5m7121feucs.apps.googleusercontent.com' : null,
    scopes: ['email', 'profile'],
  );

  // Google認証
  static Future<User?> signInWithGoogle() async {
    try {
      
      // 既存のGoogle Sign-In状態をクリア
      await _googleSignIn.signOut();

      GoogleSignInAccount? googleUser;
      
      if (kIsWeb) {
        // Web版では直接Google認証を実行（deprecation警告を回避）
        try {
          googleUser = await _googleSignIn.signInSilently();
          googleUser ??= await _googleSignIn.signIn();
        } catch (e) {
          // Web版でのエラーハンドリング
          googleUser = await _googleSignIn.signIn();
        }
      } else {
        // モバイル版では従来通り
        googleUser = await _googleSignIn.signIn();
      }
      
      if (googleUser == null) {
        return null;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      userCredential.user?.providerData.forEach((provider) {
      });
      return userCredential.user;
    } catch (e) {
      if (kIsWeb) {
        if (e.toString().contains('popup_closed_by_user')) {
          throw Exception('Google認証がキャンセルされました。ポップアップが閉じられました。');
        } else if (e.toString().contains('access_denied')) {
          throw Exception('Google認証が拒否されました。権限を確認してください。');
        } else if (e.toString().contains('invalid_client')) {
          throw Exception('Google認証の設定に問題があります。Client IDを確認してください。');
        }
      }
      rethrow;
    }
  }

  // Apple認証
  static Future<User?> signInWithApple() async {
    try {
      
      // Apple IDの認証リクエスト
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      
      // Firebase認証用のクレデンシャルを作成
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      
      // Firebaseで認証
      final UserCredential userCredential = 
          await _firebaseAuth.signInWithCredential(oauthCredential);
      
      
      // プロバイダー情報の詳細ログ
      userCredential.user?.providerData.forEach((provider) {
      });
      
      return userCredential.user;
    } catch (e) {
      rethrow;
    }
  }

  // LINE認証
  static Future<User?> signInWithLine() async {
    // Web版ではLINE認証を無効化
    if (kIsWeb) {
      throw Exception('LINE認証はWebアプリでは利用できません');
    }
    
    try {
      
      // LINEログイン
      final result = await LineSDK.instance.login();
      
      if (result.userProfile == null) {
        return null;
      }
      
      
      // Firebase Cloud Functionsを使用してカスタムトークンを取得
      final customToken = await _getCustomTokenFromLineToken(result.accessToken.value);
      
      if (customToken == null) {
        throw Exception('カスタムトークンの取得に失敗しました');
      }
      
      
      // Firebaseでカスタムトークン認証
      final UserCredential userCredential = 
          await _firebaseAuth.signInWithCustomToken(customToken);
      
      
      return userCredential.user;
    } on PlatformException catch (e) {
      // LINE SDK特有のエラーを詳しく処理
      
      switch (e.code) {
        case '3003':
          throw Exception('LINE認証がキャンセルされました。LINEアプリまたはLINE Channel IDの設定を確認してください。');
        case '3004':
          throw Exception('LINE認証に失敗しました。LINEアプリの設定を確認してください。');
        case '3005':
          throw Exception('LINE SDKの設定に問題があります。Channel IDを確認してください。');
        default:
          throw Exception('LINE認証エラー (${e.code}): ${e.message}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Instagram認証（WebView方式）- 一時的にコメント化
  /*
  static Future<User?> signInWithInstagram() async {
    try {
      
      // Instagram OAuth URLを構築
      final state = _generateNonce();
      final instagramUrl = _buildInstagramOAuthUrl(state);
      
      // ブラウザでInstagram認証ページを開く
      if (await canLaunchUrl(Uri.parse(instagramUrl))) {
        await launchUrl(
          Uri.parse(instagramUrl),
          mode: LaunchMode.externalApplication,
        );
        
        // 注意: 実際の実装では、リダイレクトURLを監視して認証コードを取得する必要があります
        // ここでは簡易的な実装として、手動でコード入力を促します
        throw Exception('Instagram認証は現在開発中です。Webベースの認証フローが必要です。');
      } else {
        throw Exception('Instagram認証URLを開けませんでした');
      }
    } catch (e) {
      rethrow;
    }
  }
  */

  // SMS認証（電話番号）
  static Future<void> signInWithPhoneNumber(
    String phoneNumber,
    Function(PhoneAuthCredential) onVerificationCompleted,
    Function(FirebaseAuthException) onVerificationFailed,
    Function(String, int?) onCodeSent,
    Function(String) onAutoRetrievalTimeout,
  ) async {
    try {
      
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {
          onVerificationCompleted(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          onVerificationFailed(e);
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          onAutoRetrievalTimeout(verificationId);
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      rethrow;
    }
  }

  // SMS認証コード確認
  static Future<User?> verifyPhoneCode(
    String verificationId,
    String smsCode,
  ) async {
    try {
      
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      
      final UserCredential userCredential = 
          await _firebaseAuth.signInWithCredential(credential);
      
      
      return userCredential.user;
    } catch (e) {
      rethrow;
    }
  }

  // サインアウト
  static Future<void> signOut() async {
    try {
      // Firebase認証をサインアウト
      await _firebaseAuth.signOut();
      
      // Google認証もサインアウト
      await _googleSignIn.signOut();
      
      // LINE認証もサインアウト（Web版ではスキップ）
      if (!kIsWeb) {
        await LineSDK.instance.logout();
      }
      
    } catch (e) {
      rethrow;
    }
  }

  // ヘルパーメソッド: ランダムnonce生成
  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // ヘルパーメソッド: SHA256ハッシュ
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // LINEトークンからカスタムトークンを取得（Firebase Cloud Functions使用）
  static Future<String?> _getCustomTokenFromLineToken(String lineToken) async {
    try {
      
      // Firebase Cloud Functions経由でカスタムトークンを取得
      final HttpsCallable callable = 
          FirebaseFunctions.instance.httpsCallable('verifyLineToken');
      
      final result = await callable.call({
        'accessToken': lineToken,
      });
      
      final customToken = result.data['customToken'] as String?;
      
      return customToken;
    } catch (e) {
      return null;
    }
  }

  // Instagram OAuth URL構築 - 一時的にコメント化
  /*
  static String _buildInstagramOAuthUrl(String state) {
    // 注意: 実際のクライアントIDとリダイレクトURIを設定する必要があります
    const clientId = 'YOUR_INSTAGRAM_CLIENT_ID';
    const redirectUri = 'YOUR_REDIRECT_URI';
    
    return 'https://api.instagram.com/oauth/authorize'
        '?client_id=$clientId'
        '&redirect_uri=$redirectUri'
        '&scope=user_profile,user_media'
        '&response_type=code'
        '&state=$state';
  }
  */

  // 現在のユーザーを取得
  static User? getCurrentUser() {
    return _firebaseAuth.currentUser;
  }

  // 認証状態の変更を監視
  static Stream<User?> get authStateChanges {
    return _firebaseAuth.authStateChanges();
  }
} 