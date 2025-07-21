import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // 通知タイプの定義
  static const String NOTIFICATION_TYPE_LIKE = 'like';
  static const String NOTIFICATION_TYPE_MATCH = 'match';
  static const String NOTIFICATION_TYPE_MESSAGE = 'message';

  bool _isInitialized = false;
  String? _fcmToken;
  
  /// 通知サービスを初期化
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Web版では限定的な初期化のみ実行
      if (kIsWeb) {
        // Web版では通知権限リクエストをスキップ
        // FCMトークン取得もスキップ（Service Worker未設定のため）
        _isInitialized = true;
        return;
      }
      
      // モバイル版の通常初期化
      // 通知権限をリクエスト
      await _requestPermission();
      
      // ローカル通知を初期化
      await _initializeLocalNotifications();
      
      // FCMトークンを取得
      await _getFCMToken();
      
      // メッセージリスナーを設定
      _setupMessageListeners();
      
      _isInitialized = true;
    } catch (e) {
    }
  }

  /// 通知権限をリクエスト
  Future<void> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

  }

  /// ローカル通知を初期化
  Future<void> _initializeLocalNotifications() async {
    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// 通知タップ時の処理
  void _onNotificationTapped(NotificationResponse details) {
    // 必要に応じてナビゲーション処理を追加
  }

  /// FCMトークンを取得
  Future<void> _getFCMToken() async {
    try {
      // 少し遅延を入れてAPNsトークンの設定を待つ
      await Future.delayed(const Duration(seconds: 2));
      
      _fcmToken = await _firebaseMessaging.getToken();
      
      if (_fcmToken != null) {
        await _updateFCMTokenOnServer(_fcmToken!);
      } else {
        // リトライロジック
        await _retryGetFCMToken();
      }
      
      // トークン更新時のリスナー
      _firebaseMessaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        _updateFCMTokenOnServer(token);
      });
    } catch (e) {
      // リトライロジック
      await _retryGetFCMToken();
    }
  }

  /// FCMトークン取得のリトライ
  Future<void> _retryGetFCMToken() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(seconds: (i + 1) * 2));
      try {
        _fcmToken = await _firebaseMessaging.getToken();
        if (_fcmToken != null) {
          await _updateFCMTokenOnServer(_fcmToken!);
          return;
        }
      } catch (e) {
      }
    }
  }

  /// FCMトークンをサーバーに更新
  Future<void> _updateFCMTokenOnServer(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable('updateFCMToken');
      await callable({'fcmToken': token}).timeout(const Duration(seconds: 10));
    } catch (e) {
    }
  }

  /// メッセージリスナーを設定
  void _setupMessageListeners() {
    // フォアグラウンドメッセージ
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    // バックグラウンドでアプリが開かれた場合
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });

    // アプリ起動時の通知
    _checkInitialMessage();
  }

  /// ローカル通知を表示
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'デフォルト通知',
      channelDescription: 'アプリからの通知',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      message.notification?.title ?? 'Dating Food App',
      message.notification?.body ?? 'メッセージが届きました',
      notificationDetails,
      payload: json.encode(message.data),
    );
  }

  /// 通知タップ時の処理
  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'];
    // 必要に応じてナビゲーション処理を追加
  }

  /// アプリ起動時の通知チェック
  Future<void> _checkInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// いいね通知を送信
  Future<bool> sendLikeNotification(String targetUserId, String senderName) async {
    return await _sendNotification(
      targetUserId: targetUserId,
      type: NOTIFICATION_TYPE_LIKE,
      title: 'デリミート',
      body: '${senderName}さんからいいねされました',
    );
  }

  /// マッチ通知を送信
  Future<bool> sendMatchNotification(String targetUserId, String senderName) async {
    return await _sendNotification(
      targetUserId: targetUserId,
      type: NOTIFICATION_TYPE_MATCH,
      title: 'デリミート',
      body: '${senderName}さんとマッチしました！',
    );
  }

  /// メッセージ通知を送信
  Future<bool> sendMessageNotification(String targetUserId, String senderName, String messagePreview) async {
    return await _sendNotification(
      targetUserId: targetUserId,
      type: NOTIFICATION_TYPE_MESSAGE,
      title: 'デリミート',
      body: '${senderName}さんからメッセージが届いています❤️',
    );
  }

  /// 通知を送信
  Future<bool> _sendNotification({
    required String targetUserId,
    required String type,
    required String title,
    required String body,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
      await callable({
        'targetUserId': targetUserId,
        'type': type,
        'title': title,
        'body': body,
        'data': {
          'type': type,
          'senderId': FirebaseAuth.instance.currentUser?.uid,
        },
      });
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 現在のFCMトークンを取得
  String? get fcmToken => _fcmToken;

  /// 通知サービスが初期化されているかチェック
  bool get isInitialized => _isInitialized;

  /// 手動でFCMトークンを再取得・更新
  Future<String?> refreshFCMToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      _fcmToken = await _firebaseMessaging.getToken();
      
      if (_fcmToken != null) {
        await _updateFCMTokenOnServer(_fcmToken!);
        return _fcmToken;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}

// バックグラウンドメッセージハンドラー（トップレベル関数）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
} 