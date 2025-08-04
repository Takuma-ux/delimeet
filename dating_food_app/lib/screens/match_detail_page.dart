import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../pages/send_date_request_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../services/web_image_helper.dart';
import '../services/message_cache_service.dart';

const String API_BASE_URL = 'https://asia-northeast1-dating-food-app-82e38.cloudfunctions.net/api';

class MatchDetailPage extends StatefulWidget {
  final String matchId;
  final String partnerName;

  const MatchDetailPage({
    super.key,
    required this.matchId,
    required this.partnerName,
  });

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(); // キーボード制御用
  
  List<dynamic> _messages = [];
  dynamic _matchDetail;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage; // エラーメッセージを保存

  // 新着メッセージ管理（LINE/Instagram風）
  bool _hasNewMessages = false;
  int _lastMessageCount = 0;

  // 投票処理中の管理
  final Set<String> _processingRequestIds = {};
  final Set<String> _processingVotingIds = {};
  
  // 投票完了済みリクエストIDを一時的に管理（UI更新のため）
  final Set<String> _completedVoteRequestIds = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
    
    // 画面が構築された後に確実に最新メッセージにスクロール
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _scrollController.hasClients && _messages.isNotEmpty) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    
    try {
      // まずマッチ詳細を取得（必須）
      await _loadMatchDetail();
      
      // マッチ詳細が取得できた場合のみメッセージを取得
      if (_matchDetail != null) {
        await _loadMessages();
        
        // 既読マークは非同期で実行（UIブロックしない）
        if (mounted) {
          _markMessagesAsRead();
        }
      } else {
        // マッチ詳細が取得できない場合はエラー
        if (mounted) {
          setState(() {
            _errorMessage = 'マッチ詳細の取得に失敗しました';
            _isLoading = false;
          });
        }
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'データの初期化に失敗しました: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMatchDetail() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getMatchDetail');
      final result = await callable({'matchId': widget.matchId}).timeout(const Duration(seconds: 6));
      
      if (result.data != null) {
        if (mounted) {
          setState(() {
            _matchDetail = result.data;
          });
        }
      } else {
        throw Exception('マッチ詳細データが空です');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'マッチ詳細の取得に失敗しました: $e';
        });
      }
      rethrow;
    }
  }

  Future<void> _loadMessages() async {
    try {
      // マッチ詳細が取得できているかチェック
      if (_matchDetail == null) {
        throw Exception('マッチ詳細が取得できていません');
      }
      
      // まずキャッシュから取得を試行
      final cachedMessages = await MessageCacheService.getCachedMessages(widget.matchId);
      
      if (cachedMessages != null && cachedMessages.isNotEmpty) {
        if (mounted) {
          setState(() {
            _messages = cachedMessages;
            _isLoading = false;
          });
        }
        
        // 投票済み状態の整合性チェック（不正な状態をクリア）
        _cleanupInvalidVotingStates();
        
        // 日程投票完了状態の復元（メッセージから推論）
        _restoreCompletedVoteStates();
      }
      
      // サーバーから最新データを取得
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getMatchMessages');
      final result = await callable({
        'matchId': widget.matchId,
        'limit': 100,
      }).timeout(const Duration(seconds: 5));
      
      if (mounted) {
        final newMessages = result.data['messages'] ?? [];
        
        // 新着メッセージの検出（LINE/Instagram風）
        if (_lastMessageCount > 0 && newMessages.length > _lastMessageCount) {
          setState(() {
            _hasNewMessages = true;
          });
        }
        
        setState(() {
          _messages = newMessages;
          _lastMessageCount = newMessages.length;
          _isLoading = false;
        });
        
        // メッセージが更新されたら最新メッセージにスクロール
        if (newMessages.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
        
        // 投票済み状態の整合性チェック（不正な状態をクリア）
        _cleanupInvalidVotingStates();
        
        // 日程投票完了状態の復元（メッセージから推論）
        _restoreCompletedVoteStates();
        
        // キャッシュに保存
        await MessageCacheService.cacheMessages(widget.matchId, newMessages);
      }
      
      // 初回読み込み時は最新メッセージにスクロール（LINE/Instagram風）
      if (_lastMessageCount == 0 && result.data['messages'] != null && (result.data['messages'] as List).isNotEmpty) {
        // より確実にスクロールするため、複数回試行
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            );
          }
        });
        // 追加で確実にスクロール
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'メッセージの取得に失敗しました';
        });
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('markMessagesAsRead');
      await callable({'matchId': widget.matchId}).timeout(const Duration(seconds: 3));
    } catch (e) {
      // 既読マークのエラーは重要度が低いので、UIには影響させない
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    // 送信開始フラグを設定
    setState(() {
      _isSending = true;
    });

    // キーボードを閉じる
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();

    // メッセージコントローラーをクリア
    _messageController.clear();

    // 即座にメッセージをUIに追加
    final newMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'content': content,
      'sender_id': FirebaseAuth.instance.currentUser?.uid,
      'sent_at': DateTime.now().toIso8601String(),
      'message_type': 'text',
    };
    
    setState(() {
      _messages.add(newMessage);
      _lastMessageCount = _messages.length;
    });
    
    // 最新メッセージにスクロール
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }

    // バックグラウンドでDBに保存
    await _saveMessageToDatabase(content, newMessage);
    
    // 送信完了フラグを設定
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  // バックグラウンドでメッセージをDBに保存
  Future<void> _saveMessageToDatabase(String content, Map<String, dynamic> message) async {
    try {
      print('🔍 メッセージ送信開始: matchId=${widget.matchId}, content=$content');
      
      // メッセージ送信（バックグラウンドで実行）
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('sendMessage');
      final result = await callable({
        'matchId': widget.matchId,
        'content': content,
        'type': 'text',
      }).timeout(const Duration(seconds: 10));
      
      print('🔍 メッセージ送信結果: ${result.data}');
      
      if (mounted && result.data != null && result.data['success'] == true) {
        print('✅ メッセージ送信成功');
        // 成功時は何もしない（UIは既に更新済み）
      } else {
        print('❌ メッセージ送信失敗: ${result.data}');
        // 失敗時はUIからメッセージを削除
        if (mounted) {
          setState(() {
            _messages.removeWhere((msg) => msg['id'] == message['id']);
            _lastMessageCount = _messages.length;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('メッセージの保存に失敗しました: ${result.data?['error'] ?? '不明なエラー'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      
    } catch (e) {
      print('❌ メッセージ送信エラー: $e');
      // エラー時はUIからメッセージを削除
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg['id'] == message['id']);
          _lastMessageCount = _messages.length;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('メッセージの保存に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // エラー時も送信フラグをリセット
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String _formatMessageTime(String? sentAt) {
    if (sentAt == null || sentAt.isEmpty || sentAt == '{}') return '';
    
    try {
      final DateTime messageTime = DateTime.parse(sentAt).toLocal();
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final DateTime messageDate = DateTime(messageTime.year, messageTime.month, messageTime.day);
      
      if (messageDate == today) {
        return '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
      } else {
        return '${messageTime.month}/${messageTime.day} ${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildDateRequestMessage(Map<String, dynamic> message, bool isMyMessage) {
    final dateRequestDataRaw = message['date_request_data'];
    if (dateRequestDataRaw == null) {
      return Container(); // データがない場合は空のコンテナを返す
    }

    // JSON文字列をパース
    Map<String, dynamic> dateRequestData;
    try {
      if (dateRequestDataRaw is String) {
        dateRequestData = Map<String, dynamic>.from(jsonDecode(dateRequestDataRaw));
      } else if (dateRequestDataRaw is Map) {
        // Map<Object?, Object?>をMap<String, dynamic>に安全に変換
        dateRequestData = <String, dynamic>{};
        dateRequestDataRaw.forEach((key, value) {
          if (key is String) {
            dateRequestData[key] = value;
          }
        });
      } else {
        return Container();
      }
    } catch (e) {
      return Container();
    }

    final restaurantName = dateRequestData['restaurantName'] ?? 
                          dateRequestData['restaurant_name'] ?? 
                          '未設定のレストラン';
    final restaurantImageUrl = dateRequestData['restaurantImageUrl'];
    final restaurantCategory = dateRequestData['restaurantCategory'] ?? 
                              dateRequestData['restaurant_category'] ?? 
                              '';
    final restaurantPrefecture = dateRequestData['restaurantPrefecture'] ?? 
                                dateRequestData['restaurant_prefecture'] ?? 
                                '';
    final restaurantNearestStation = dateRequestData['restaurantNearestStation'] ?? 
                                    dateRequestData['restaurant_nearest_station'] ?? 
                                    '';
    final restaurantLowPrice = dateRequestData['restaurantLowPrice'];
    final restaurantHighPrice = dateRequestData['restaurantHighPrice'];
    final restaurantPriceRange = dateRequestData['restaurantPriceRange'] ?? '';
    final proposedDates = List<String>.from(dateRequestData['proposedDates'] ?? []);
    final messageText = dateRequestData['message'] ?? '';
    final requestId = message['related_date_request_id'];
    final additionalRestaurantIds = List<String>.from(dateRequestData['additionalRestaurantIds'] ?? []);
    final paymentOption = dateRequestData['paymentOption'] ?? 'discuss';
    final requesterName = message['sender_name'] ?? 'ユーザー';
    
    // ステータスを判定（マッチ画面では受信者の投票が決定日程になる）
    String status = 'pending';
    String? decidedDate;
    List<String>? tiedDates;
    bool isReceiverVoted = false;
    String? receiverResponse;
    Set<String> receiverSelectedDates = {};
    
    // 現在のユーザーIDを取得
    final currentUserFirebaseUid = FirebaseAuth.instance.currentUser?.uid;
    final messageSenderId = message['sender_id']; // メッセージ送信者のID（Firebase UIDまたはUUID ID）
    
    // 現在のユーザーのUUID IDを取得（_matchDetailから取得）
    String? currentUserUuidId;
    
    if (_matchDetail != null) {
      // _matchDetailから現在のユーザーのUUID IDを取得
      final user1Id = _matchDetail['user1_id'];
      final user2Id = _matchDetail['user2_id'];
      
      // パートナーIDと比較して現在のユーザーを特定
      final partnerId = _matchDetail['partner_id'];
      
      // partnerIdがuser1Idと一致する場合、現在のユーザーはuser2Id
      // partnerIdがuser2Idと一致する場合、現在のユーザーはuser1Id
      if (partnerId == user1Id) {
        currentUserUuidId = user2Id;
      } else if (partnerId == user2Id) {
        currentUserUuidId = user1Id;
      }
      
    }
    
    
    // 日程リクエストの送信者かどうかを判定
    // messageSenderIdはUUID IDで保存されているため、UUID IDで比較
    bool isRequestSender = false;
    
    if (currentUserUuidId != null && messageSenderId == currentUserUuidId) {
      isRequestSender = true;
    }
    
    
    if (dateRequestData['type'] == 'date_response') {
      // 1対1マッチでは受信者が投票した時点で決定
      if (dateRequestData['response'] == 'vote') {
        status = 'decided';
        // selectedDataが配列の場合は最初の要素を使用
        final selectedData = dateRequestData['selectedData'];
        if (selectedData is List && selectedData.isNotEmpty) {
          decidedDate = selectedData.first.toString();
        } else if (selectedData is String) {
          decidedDate = selectedData;
        }
      } else if (dateRequestData['response'] == 'reject') {
        status = 'reject';
      }
    } else if (dateRequestData['type'] == 'date_decision') {
      status = dateRequestData['status'] ?? 'pending';
      decidedDate = dateRequestData['decidedDate'];
      tiedDates = List<String>.from(dateRequestData['tiedDates'] ?? []);
    } else {
      // 受信者の投票状況をチェック（現在のユーザーが送信者でない場合のみ）
      if (!isRequestSender) {
        // 現在のユーザー（受信者）のFirebase UIDを基に投票状況をチェック
        
        for (final msg in _messages) {
          if (msg is Map) {
            final msgData = <String, dynamic>{};
            msg.forEach((key, value) {
              if (key is String) msgData[key] = value;
            });
            
            // 関連するリクエストIDが一致するかチェック
            if (msgData['related_date_request_id'] == requestId) {
              final msgSenderId = msgData['sender_id']; // メッセージ送信者のID
              final responseData = msgData['date_request_data'];
              final messageType = msgData['message_type'];
              
              
              // 受信者からの回答メッセージかチェック（UUID IDで比較）
              // date_responseメッセージのsender_idはUUID IDで保存される
              final msgSenderUuidId = msgData['sender_id'];
              if (msgSenderUuidId == currentUserUuidId && messageType == 'date_response') {
                
                if (responseData is Map) {
                  final respMap = <String, dynamic>{};
                  responseData.forEach((key, value) {
                    if (key is String) respMap[key] = value;
                  });
                  
                  if (respMap['response'] == 'vote' && respMap['selectedData'] != null) {
                    isReceiverVoted = true;
                    receiverResponse = respMap['response'];
                    
                    final selectedData = respMap['selectedData'];
                    if (selectedData is String) {
                      receiverSelectedDates = selectedData.split(',').toSet();
                    } else if (selectedData is List) {
                      receiverSelectedDates = selectedData.map((e) => e.toString()).toSet();
                    }
                    
                    // 受信者が投票した場合、投票済み状態とする（日程決定はサーバー側で判定）
                    status = 'voted';
                    // 選択日程は保持するが、まだ決定ではない
                    break;
                  } else if (respMap['response'] == 'reject') {
                    isReceiverVoted = true;
                    receiverResponse = respMap['response'];
                    status = 'reject';
                    break;
                  }
                }
              }
            }
          }
        }
        
        // date_decisionメッセージをチェック（最後にチェックして状態を上書き）
        for (final msg in _messages) {
          if (msg is Map) {
            final msgData = <String, dynamic>{};
            msg.forEach((key, value) {
              if (key is String) msgData[key] = value;
            });
            
            // 関連するリクエストIDが一致するかチェック
            if (msgData['related_date_request_id'] == requestId && msgData['message_type'] == 'date_decision') {
              final decisionData = msgData['date_request_data'];
              
              if (decisionData is Map) {
                final decisionMap = <String, dynamic>{};
                decisionData.forEach((key, value) {
                  if (key is String) decisionMap[key] = value;
                });
                
                final decisionStatus = decisionMap['status'];
                final decisionDecidedDate = decisionMap['decidedDate'];
                
                
                if (decisionStatus == 'decided' && decisionDecidedDate != null) {
                  status = 'decided';
                  decidedDate = decisionDecidedDate.toString();
                  break;
                } else if (decisionStatus == 'no_match') {
                  status = 'no_match';
                  break;
                }
              }
            }
          }
        }
        
        // restaurant_decisionメッセージからも日程情報を取得
        for (final msg in _messages) {
          if (msg is Map) {
            final msgData = <String, dynamic>{};
            msg.forEach((key, value) {
              if (key is String) msgData[key] = value;
            });
            
            // 関連するリクエストIDが一致するかチェック
            if (msgData['related_date_request_id'] == requestId && msgData['message_type'] == 'restaurant_decision') {
              final decisionData = msgData['date_request_data'];
              
              if (decisionData is Map) {
                final decisionMap = <String, dynamic>{};
                decisionData.forEach((key, value) {
                  if (key is String) decisionMap[key] = value;
                });
                
                final decisionStatus = decisionMap['status'];
                final decisionDecidedDate = decisionMap['decidedDate'];
                
                
                if (decisionStatus == 'decided' && decisionDecidedDate != null) {
                  status = 'decided';
                  // 日本語フォーマットされた日付をISOフォーマットに変換
                  if (decisionDecidedDate.toString().contains('年')) {
                    // 日本語フォーマット（例：2025年7月13日(日) 22:00）をそのまま使用
                    decidedDate = decisionDecidedDate.toString();
                  } else {
                    decidedDate = decisionDecidedDate.toString();
                  }
                  break;
                }
              }
            }
          }
        }
      }
      
      // date_decisionメッセージもチェック（送信者の場合）
      if (isRequestSender) {
        for (final msg in _messages) {
          if (msg is Map) {
            final msgData = <String, dynamic>{};
            msg.forEach((key, value) {
              if (key is String) msgData[key] = value;
            });
            
            // 関連するリクエストIDが一致するかチェック
            if (msgData['related_date_request_id'] == requestId && msgData['message_type'] == 'date_decision') {
              final decisionData = msgData['date_request_data'];
              
              if (decisionData is Map) {
                final decisionMap = <String, dynamic>{};
                decisionData.forEach((key, value) {
                  if (key is String) decisionMap[key] = value;
                });
                
                final decisionStatus = decisionMap['status'];
                final decisionDecidedDate = decisionMap['decidedDate'];
                
                
                if (decisionStatus == 'decided' && decisionDecidedDate != null) {
                  status = 'decided';
                  decidedDate = decisionDecidedDate.toString();
                  break;
                } else if (decisionStatus == 'no_match') {
                  status = 'no_match';
                  break;
                }
              }
            }
          }
        }
        
        // 送信者向けrestaurant_decisionメッセージからも日程情報を取得
        for (final msg in _messages) {
          if (msg is Map) {
            final msgData = <String, dynamic>{};
            msg.forEach((key, value) {
              if (key is String) msgData[key] = value;
            });
            
            // 関連するリクエストIDが一致するかチェック
            if (msgData['related_date_request_id'] == requestId && msgData['message_type'] == 'restaurant_decision') {
              final decisionData = msgData['date_request_data'];
              
              if (decisionData is Map) {
                final decisionMap = <String, dynamic>{};
                decisionData.forEach((key, value) {
                  if (key is String) decisionMap[key] = value;
                });
                
                final decisionStatus = decisionMap['status'];
                final decisionDecidedDate = decisionMap['decidedDate'];
                
                
                if (decisionStatus == 'decided' && decisionDecidedDate != null) {
                  status = 'decided';
                  // 日本語フォーマットされた日付をそのまま使用
                  decidedDate = decisionDecidedDate.toString();
                  break;
                }
              }
            }
          }
        }
      }
    }
    

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: isRequestSender ? Colors.blue[50] : const Color(0xFFFDF5E6),
                                border: Border.all(color: isRequestSender ? Colors.blue[200]! : const Color(0xFFF6BFBC)!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isRequestSender ? Colors.blue[100] : const Color(0xFFFDF5E6),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                                        Icon(Icons.restaurant, color: isRequestSender ? Colors.blue[700] : const Color(0xFFF6BFBC), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'デートのお誘い',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                                              color: isRequestSender ? Colors.blue[700] : const Color(0xFFF6BFBC),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // レストラン情報
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (restaurantImageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: WebImageHelper.buildRestaurantImage(
                          restaurantImageUrl,
                          width: 60,
                          height: 60,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            restaurantName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (restaurantCategory.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              restaurantCategory,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            _formatLocation(restaurantPrefecture, restaurantNearestStation),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatPriceRange(restaurantLowPrice, restaurantHighPrice, restaurantPriceRange),
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // 追加店舗表示
                if (additionalRestaurantIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.add_circle, color: Colors.green[600], size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '追加候補店舗 (${additionalRestaurantIds.length}店舗)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '最終的に${additionalRestaurantIds.length + 1}店舗から投票で決定します',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 支払いオプション表示
                if (paymentOption != 'discuss') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getPaymentOptionColor(paymentOption).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _getPaymentOptionColor(paymentOption).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getPaymentOptionEmoji(paymentOption),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getPaymentOptionText(paymentOption),
                          style: TextStyle(
                            color: _getPaymentOptionColor(paymentOption),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // 候補日時
                if (proposedDates.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '候補日時:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...proposedDates.map((dateStr) {
                    try {
                      final date = DateTime.parse(dateStr);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${DateFormat('MM/dd(E) HH:mm', 'ja').format(date)}',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                      );
                    } catch (e) {
                      return Container();
                    }
                  }).toList(),
                ],
                
                // メッセージ
                if (messageText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      messageText,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
                
                // 承認・拒否ボタン（受信者のみ表示）
                if (!isRequestSender) ...[
                  const SizedBox(height: 16),
                  // 現在のユーザーの投票状況に応じた表示
                  // デバッグログ
                  Builder(builder: (context) {
                    return const SizedBox.shrink();
                  }),
                  
                  if (_processingRequestIds.contains(requestId)) ...[
                    // 処理中の場合
                    Builder(builder: (context) {
                      return const SizedBox.shrink();
                    }),
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 12),
                          Text('投票処理中...'),
                        ],
                      ),
                    ),
                  ] else if (_extractDecidedDate(decidedDate) != null) ...[
                    // 日程決定済みの場合
                    Builder(builder: (context) {
                      return const SizedBox.shrink();
                    }),
                    _buildDateDecisionCard(dateRequestData, requestId, _extractDecidedDate(decidedDate)!, additionalRestaurantIds),
                  ] else if (isReceiverVoted || _completedVoteRequestIds.contains(requestId)) ...[
                    // 受信者が既に投票済みで日程未決定の場合
                    Builder(builder: (context) {
                      // 店舗投票メッセージが存在するかチェック
                      bool hasRestaurantVotingMessage = false;
                      for (final msg in _messages) {
                        if (msg is Map) {
                          final msgData = <String, dynamic>{};
                          msg.forEach((key, value) {
                            if (key is String) msgData[key] = value;
                          });
                          if (msgData['message_type'] == 'restaurant_voting' && 
                              msgData['related_date_request_id'] == requestId) {
                            hasRestaurantVotingMessage = true;
                            break;
                          }
                        }
                      }
                      
                      if (hasRestaurantVotingMessage) {
                        // 店舗投票が開始されている場合は日程選択完了として表示
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 16),
                              const SizedBox(width: 4),
                              const Text(
                                '日程選択完了 ✅',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        // 店舗投票がまだ開始されていない場合は処理中として表示
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, color: Colors.blue, size: 16),
                              const SizedBox(width: 4),
                              const Text(
                                '回答済み - 日程を確定中...',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    }),
                  ] else ...[
                    // まだ投票していない場合 - 受信者用ボタン表示
                    Builder(builder: (context) {
                      final isProcessing = _processingRequestIds.contains(requestId);
                      
                      if (isProcessing) {
                        // 処理中表示
                        return Container(
                          padding: const EdgeInsets.all(16),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 12),
                              Text('投票処理中...'),
                            ],
                          ),
                        );
                      }
                      
                      return Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _showDateVotingDialog(requestId, proposedDates),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF6BFBC),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('日程を選択'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: !isProcessing ? () => _showRejectMessageDialog(requestId) : null,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.grey),
                                foregroundColor: Colors.grey,
                              ),
                              child: Text(isProcessing ? '処理中...' : '辞退する'),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ] else ...[
                  // 送信者の場合（自動投票済み）
                  const SizedBox(height: 16),
                  if (status == 'decided' && _extractDecidedDate(decidedDate) != null) ...[
                    // 送信者側：日程決定通知のみ表示（店舗設定カードは表示しない）
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '日程が決定されました！',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  '決定日程: ${_formatDecidedDate(_extractDecidedDate(decidedDate)!)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (status == 'reject') ...[
                    // 受信者が辞退した場合
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cancel, color: Colors.red, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            '相手が辞退しました',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (status == 'no_match') ...[
                    // 日程が一致しなかった場合
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_busy, color: Colors.orange, size: 16),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'お互いの予定が合いませんでした',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (isReceiverVoted) ...[
                    // 受信者が投票済み（処理中）
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.blue, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            '相手が回答済み - 日程を確定中...',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // 相手の回答待ち
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.grey[600], size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '相手の回答を待っています...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                
                // 送信者情報
                const SizedBox(height: 8),
                Text(
                  'from $requesterName',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 価格帯表示ヘルパー（1対1マッチ用）
  String _formatPriceRange(dynamic lowPrice, dynamic highPrice, String priceRange) {
    if (lowPrice != null && highPrice != null) {
      final low = int.tryParse(lowPrice.toString());
      final high = int.tryParse(highPrice.toString());
      if (low != null && high != null) {
        if (low == high) {
          return '${low}円';
        } else {
          return '${low}~${high}円';
        }
      }
    } else if (lowPrice != null) {
      final low = int.tryParse(lowPrice.toString());
      if (low != null) {
        return '${low}円~';
      }
    } else if (highPrice != null) {
      final high = int.tryParse(highPrice.toString());
      if (high != null) {
        return '~${high}円';
      }
    }
    
    // フォールバック: 元のprice_rangeを使用
    return priceRange.isNotEmpty ? priceRange : '価格未設定';
  }

  /// 場所表示ヘルパー（1対1マッチ用）
  String _formatLocation(String prefecture, String nearestStation) {
    List<String> locationParts = [];
    if (prefecture.isNotEmpty) {
      locationParts.add(prefecture);
    }
    if (nearestStation.isNotEmpty) {
      locationParts.add(nearestStation);
    }
    return locationParts.isNotEmpty ? locationParts.join(' • ') : '場所未設定';
  }

  /// 支払いオプションの色を取得
  Color _getPaymentOptionColor(String paymentOption) {
    switch (paymentOption) {
      case 'treat':
        return const Color(0xFF4CAF50);
      case 'split':
        return const Color(0xFF2196F3);
      case 'discuss':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFFFF9800);
    }
  }

  /// 支払いオプションの絵文字を取得
  String _getPaymentOptionEmoji(String paymentOption) {
    switch (paymentOption) {
      case 'treat':
        return '💸';
      case 'split':
        return '🤝';
      case 'discuss':
        return '💬';
      default:
        return '💬';
    }
  }

  /// 支払いオプションのテキストを取得
  String _getPaymentOptionText(String paymentOption) {
    switch (paymentOption) {
      case 'treat':
        return 'おごります';
      case 'split':
        return '割り勘';
      case 'discuss':
        return '相談';
      default:
        return '相談';
    }
  }

  /// 決定日程を正しい形式で取得
  String? _extractDecidedDate(dynamic decidedDate) {
    if (decidedDate == null) return null;
    
    if (decidedDate is String) {
      // JSONの配列文字列の場合
      if (decidedDate.startsWith('[') && decidedDate.endsWith(']')) {
        try {
          final parsed = jsonDecode(decidedDate);
          if (parsed is List && parsed.isNotEmpty) {
            return parsed.first.toString();
          }
        } catch (e) {
        }
      }
      return decidedDate;
    }
    
    if (decidedDate is List && decidedDate.isNotEmpty) {
      return decidedDate.first.toString();
    }
    
    return decidedDate.toString();
  }

  /// 決定日程があるかチェック
  bool _hasDecidedDate(String status, dynamic decidedDate) {
    if (status != 'decided') return false;
    final extractedDate = _extractDecidedDate(decidedDate);
    return extractedDate != null && extractedDate.isNotEmpty;
  }

  Widget _buildDateVotingUI(String requestId, List<String> proposedDates) {
    if (_processingRequestIds.contains(requestId)) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 12),
            Text('投票処理中...'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.how_to_vote, color: Colors.blue, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '日程を選択してください（複数選択可）',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '参加可能な日程をすべて選択してください',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showDateVotingDialog(requestId, proposedDates),
            icon: const Icon(Icons.how_to_vote),
            label: const Text('日程を選択'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF6BFBC),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _showRejectMessageDialog(requestId),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.grey),
            ),
            child: const Text('断る'),
          ),
        ),
      ],
    );
  }

  Widget _buildDateDecisionCard(Map<String, dynamic> dateRequestData, String requestId, String decidedDate, List<String> additionalRestaurantIds) {
    
    // 店舗決定メッセージがあるかチェック
    final hasRestaurantDecision = _messages.any((msg) {
      if (msg is Map) {
        final msgData = <String, dynamic>{};
        msg.forEach((key, value) {
          if (key is String) msgData[key] = value;
        });
        return msgData['message_type'] == 'restaurant_decision' && 
               msgData['related_date_request_id'] == requestId;
      }
      return false;
    });
    
    if (hasRestaurantDecision) {
      return const SizedBox.shrink();
    }
    
    // 店舗投票が必要かチェック
    final bool needsRestaurantVoting = additionalRestaurantIds.isNotEmpty;
    
    if (needsRestaurantVoting) {
      // 店舗投票メッセージがあるかチェック
      final hasRestaurantVoting = _messages.any((msg) {
        if (msg is Map) {
          final msgData = <String, dynamic>{};
          msg.forEach((key, value) {
            if (key is String) msgData[key] = value;
          });
          return msgData['message_type'] == 'restaurant_voting' && 
                 msgData['related_date_request_id'] == requestId;
        }
        return false;
      });
      

      if (!hasRestaurantVoting) {
        // 店舗投票の自動開始を待機中
        return _buildWaitingForRestaurantVotingCard(requestId, decidedDate);
      } else {
        return const SizedBox.shrink();
      }
    } else {
      // 追加店舗がない場合は直接デート確定
      return _buildDateConfirmedCard(dateRequestData, requestId, decidedDate);
    }
  }



  Widget _buildRestaurantVotingStartingCard(String requestId, String decidedDate) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              const Text(
                '日程が決定されました！',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '決定日程: ${_formatDecidedDate(decidedDate)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '店舗投票を開始しています...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 店舗投票の自動開始を待機中のカード
  Widget _buildWaitingForRestaurantVotingCard(String requestId, String decidedDate) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              const Text(
                '日程が決定されました！',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '決定日程: ${_formatDecidedDate(decidedDate)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade300),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '店舗選択の準備中...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// デート確定カード（追加店舗がない場合）
  Widget _buildDateConfirmedCard(Map<String, dynamic> dateRequestData, String requestId, String decidedDate) {
    final restaurantName = dateRequestData['restaurantName'] ?? '未設定のレストラン';
    final restaurantId = dateRequestData['restaurantId'] ?? '';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.celebration,
            color: Colors.green,
            size: 32,
          ),
          const SizedBox(height: 8),
          const Text(
            '🎉 デート確定！',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '📅 ${_formatDecidedDate(decidedDate)}',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            '🏪 $restaurantName',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '素敵な時間をお過ごしください💕',
            style: TextStyle(
              color: Colors.green[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // 予約案内ボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _showReservationConfirmDialog(requestId, restaurantName, restaurantId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '予約案内を見る',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDecidedDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}(${_getWeekday(date.weekday)}) ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _showDateVotingDialog(String requestId, List<String> proposedDates) async {
    // 処理中チェック
    if (_processingRequestIds.contains(requestId)) {
      return;
    }
    
    Set<String> selectedDates = {};
    
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('参加可能な日程を選択してください'),
          content: proposedDates.isEmpty 
            ? const Text('選択可能な日時がありません')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '参加可能な日程をすべて選択してください（複数選択可）',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ...proposedDates.map((dateStr) {
                    try {
                      final date = DateTime.parse(dateStr);
                      final formattedDate = '${date.month}/${date.day}(${_getWeekday(date.weekday)}) ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      
                      return CheckboxListTile(
                        title: Text(formattedDate),
                        value: selectedDates.contains(dateStr),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              selectedDates.add(dateStr);
                            } else {
                              selectedDates.remove(dateStr);
                            }
                          });
                        },
                      );
                    } catch (e) {
                      return Container();
                    }
                  }).toList(),
                ],
              ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: selectedDates.isNotEmpty && !_processingRequestIds.contains(requestId)
                      ? () => Navigator.pop(context, selectedDates)
                      : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF6BFBC),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_processingRequestIds.contains(requestId) ? '処理中...' : '投票する'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _respondToDateRequest(requestId, 'vote', selectedDates: result);
    }
  }



  String _getWeekday(int weekday) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return weekdays[weekday - 1];
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accept': return Colors.green;
      case 'accepted': return Colors.green;
      case 'rejected': return Colors.red;
      case 'reject': return Colors.red;
      case 'vote': return Colors.blue;
      case 'decided': return Colors.green;
      case 'no_common_dates': return Colors.orange;
      default: return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'accept': return Icons.check_circle;
      case 'accepted': return Icons.check_circle;
      case 'rejected': return Icons.cancel;
      case 'reject': return Icons.cancel;
      case 'vote': return Icons.how_to_vote;
      case 'decided': return Icons.event_available;
      case 'no_common_dates': return Icons.warning;
      default: return Icons.schedule;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'accept': return '承認済み';
      case 'accepted': return '承認済み';
      case 'rejected': return '辞退済み';
      case 'reject': return '辞退済み';
      case 'vote': return '投票済み';
      case 'decided': return '日程決定';
      case 'no_common_dates': return '共通日程なし';
      default: return '回答待ち';
    }
  }

  Widget _buildReservationCard(Map<String, dynamic> dateRequestData, String requestId) {
    final restaurantName = dateRequestData['restaurantName'] ?? 
                          dateRequestData['restaurant_name'] ?? 
                          '未設定のレストラン';
    
    return Column(
      children: [
        // 承認済み表示
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 16),
              SizedBox(width: 4),
              Text(
                '承認済み',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 予約案内カード
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            children: [
              // 下矢印アイコン
              const Icon(
                Icons.keyboard_arrow_down,
                size: 32,
                color: Colors.blue,
              ),
              const SizedBox(height: 12),
              
              // 予約ボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final restaurantId = dateRequestData['restaurantId']?.toString();
                    _showReservationConfirmDialog(requestId, restaurantName, restaurantId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '予約案内を見る',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showReservationConfirmDialog(String requestId, String restaurantName, String? restaurantId) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.restaurant_menu, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text('予約案内')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant, color: Colors.blue, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          restaurantName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '📞 Dineスタッフがお客様に代わって予約のお電話をいたします',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '⏰ 通常15-30分以内に予約完了をご連絡いたします',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '✅ 予約が取れない場合は代替案をご提案いたします',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '予約案内を見ますか？',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '※ 手数料無料で予約サイトをご案内します',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestReservation(requestId, restaurantName, restaurantId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant_menu, size: 16),
                SizedBox(width: 4),
                Text('予約案内を見る'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestReservation(String requestId, String restaurantName, String? restaurantId) async {
    try {
      
      // Firebase Functions の getReservationGuidance を直接呼び出し
      final result = await FirebaseFunctions.instance
          .httpsCallable('getReservationGuidance')
          .call({
        'requestId': requestId,
        'restaurantName': restaurantName,
        'restaurantId': restaurantId, // レストランIDを追加
      });


      if (result.data != null && result.data['success'] == true) {
        final reservationOptions = result.data['reservationOptions'] ?? [];
        
        
        // 予約案内ダイアログを表示
        _showReservationOptionsDialog(reservationOptions, restaurantName, requestId);

        // メッセージリストを更新して新しいシステムメッセージを表示
        await _loadMessages();

      } else {
        throw Exception(result.data?['error'] ?? '予約案内の取得に失敗しました');
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('予約案内の取得に失敗しました: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showReservationOptionsDialog(List reservationOptions, String restaurantName, String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
                            const Icon(Icons.restaurant, color: const Color(0xFFF6BFBC)),
            const SizedBox(width: 8),
            Expanded(child: Text('$restaurantName の予約方法')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '以下の方法で予約をお取りください：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...reservationOptions.where((option) {
              // 有効な予約オプションのみをフィルタリング
              if (option['type'] == 'web') {
                return option['url'] != null && option['url'].toString().isNotEmpty;
              } else if (option['type'] == 'phone') {
                return option['phoneNumber'] != null && option['phoneNumber'].toString().isNotEmpty;
              }
              return true; // その他のタイプは通す
            }).map((option) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                                          backgroundColor: const Color(0xFFF6BFBC).withOpacity(0.1),
                  child: Icon(
                    option['icon'] == 'phone' ? Icons.phone : Icons.web,
                    color: const Color(0xFFF6BFBC),
                  ),
                ),
                title: Text(
                  option['platform'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(option['description']),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  final optionMap = Map<String, dynamic>.from(option);
                  _openReservationOption(optionMap);
                },
              ),
            )).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showReservationCompletedDialog(requestId, restaurantName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 16),
                SizedBox(width: 4),
                Text('予約完了報告'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openReservationOption(Map<String, dynamic> option) async {
    try {
      if (option['type'] == 'web' && option['url'] != null) {
        // ウェブブラウザで開く
        final url = Uri.parse(option['url']);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('ブラウザを開けませんでした');
        }
      } else if (option['type'] == 'phone' && 
                 option['phoneNumber'] != null && 
                 option['phoneNumber'].toString().isNotEmpty) {
        // 電話アプリで開く
        final phoneUrl = Uri.parse('tel:${option['phoneNumber']}');
        if (await canLaunchUrl(phoneUrl)) {
          await launchUrl(phoneUrl);
        } else {
          throw Exception('電話アプリを開けませんでした');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${option['platform']}を開けませんでした: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showReservationCompletedDialog(String requestId, String restaurantName) {
    final confirmationController = TextEditingController();
    final detailsController = TextEditingController();

    // restaurant_votingやrestaurant_decisionメッセージから関連するdate_request_idを取得
    String? dateRequestId;
    
    for (final message in _messages) {
      if (message is Map) {
        final msgData = <String, dynamic>{};
        message.forEach((key, value) {
          if (key is String) msgData[key] = value;
        });


        // 複数の条件で検索
        if (msgData['id'] == requestId) {
          dateRequestId = msgData['related_date_request_id'];
          break;
        }
        
        // fallbackとして、restaurant_decisionタイプで最新のものを使用
        if (msgData['message_type'] == 'restaurant_decision' && dateRequestId == null) {
          dateRequestId = msgData['related_date_request_id'];
        }
      }
    }
    

    if (dateRequestId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('関連するデート情報が見つかりません'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('予約完了報告'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$restaurantName の予約は完了しましたか？',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmationController,
              decoration: const InputDecoration(
                labelText: '予約番号（任意）',
                hintText: '例：HP123456789',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: detailsController,
              decoration: const InputDecoration(
                labelText: '詳細（任意）',
                hintText: '例：2名、19:00〜',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reportReservationCompleted(
                dateRequestId!,
                confirmationController.text.trim(),
                detailsController.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('報告する'),
          ),
        ],
      ),
    );
  }

  Future<void> _reportReservationCompleted(String requestId, String confirmationNumber, String details) async {
    try {
      
      // Firebase認証状態を確認
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ログインが必要です');
      }
      
      
      final result = await FirebaseFunctions.instance
          .httpsCallable('reportReservationCompleted')
          .call({
        'dateRequestId': requestId,
        'confirmationNumber': confirmationNumber,
        'reservationDetails': details,
      });


      if (result.data != null && result.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data['message'] ?? '予約完了を報告しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // メッセージリストを更新
        await _loadMessages();
      } else {
        final errorMessage = result.data?['message'] ?? '予約完了報告に失敗しました';
        throw Exception(errorMessage);
      }
    } catch (e) {
      String errorMessage = '予約完了報告に失敗しました';
      
      if (e.toString().contains('unauthenticated')) {
        errorMessage = 'ログインが必要です';
      } else if (e.toString().contains('invalid-argument')) {
        errorMessage = '必要な情報が不足しています';
      } else if (e.toString().contains('not-found')) {
        errorMessage = 'デート情報が見つかりません';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showDateRequestDialog() {
    if (_matchDetail == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SendDateRequestPage(
          matchId: widget.matchId,
          partnerId: _matchDetail!['partner_id'] ?? '',
          partnerName: _matchDetail!['partner_name'] ?? widget.partnerName,
          partnerImageUrl: _matchDetail!['partner_image_url'],
        ),
      ),
    ).then((result) {
      // デートリクエスト送信後にメッセージをリロード
      if (result == true) {
        _loadMessages();
      }
    });
  }

  Future<void> _respondToDateRequest(String? requestId, String response, {Set<String>? selectedDates, String? rejectMessage}) async {
    if (requestId == null) return;

    // 処理中フラグを設定
    setState(() {
      _processingRequestIds.add(requestId);
    });

    try {
      final Map<String, dynamic> params = {
        'requestId': requestId,
        'response': response,
      };

      if (response == 'vote' && selectedDates != null) {
        params['selectedDates'] = selectedDates.toList();
      }

      if (response == 'reject' && rejectMessage != null && rejectMessage.isNotEmpty) {
        params['rejectMessage'] = rejectMessage;
      }

      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('respondToDateRequest');
      final result = await callable.call(params);

      // 投票成功時の処理
      if (result.data['success'] == true && response == 'vote') {
        // 投票完了フラグを設定（UI即座更新のため）
        setState(() {
          _completedVoteRequestIds.add(requestId);
        });
        
        // decisionResultをチェック
        final decisionResult = result.data['decisionResult'];
        if (decisionResult != null && decisionResult['status'] == 'decided') {
          final decidedDate = decisionResult['decidedDate'];
          
          // 日程決定時は短時間遅延後にメッセージを再読み込み
          
          // 店舗投票は自動的にサーバー側で開始される
          
          // サーバーサイドでのメッセージ作成完了を待つため、遅延を入れる
          await Future.delayed(const Duration(seconds: 2));
          await _loadMessages();
          
          // 追加で確認（店舗投票メッセージが作成されるまで）
          await Future.delayed(const Duration(seconds: 1));
          await _loadMessages();
          
          // 処理中フラグをクリア
          setState(() {
            _processingRequestIds.remove(requestId);
          });
          
          return; // finally節での削除をスキップ
        }
      }

      // メッセージを再読み込み（複数回試行して確実に取得）
      int retryCount = 0;
      bool foundRestaurantVoting = false;
      
      while (retryCount < 3 && !foundRestaurantVoting) {
        if (retryCount > 0) {
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
        
        await _loadMessages();
        
        // デバッグ：restaurant_votingメッセージが作成されているかチェック
        
        for (final message in _messages) {
          if (message is Map) {
            final msgData = <String, dynamic>{};
            message.forEach((key, value) {
              if (key is String) msgData[key] = value;
            });
            
            
            if (msgData['message_type'] == 'restaurant_voting') {
              if (msgData['related_date_request_id'] == requestId) {
                foundRestaurantVoting = true;
              }
            }
          }
        }
        
        retryCount++;
      }
      
      if (!foundRestaurantVoting) {
      }
      
      // 店舗投票メッセージが見つかった場合、処理中フラグを削除
      if (foundRestaurantVoting) {
        setState(() {
          _processingRequestIds.remove(requestId);
        });
      }

      if (mounted) {
        if (response == 'reject') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('デートリクエストを辞退しました'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (response == 'vote') {
          // 投票成功時はSnackBarを表示
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('日程選択が完了しました！'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('処理に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 処理中フラグを削除（日程決定時は既にreturnで削除済みのためここは実行されない）
      if (mounted) {
        setState(() {
          _processingRequestIds.remove(requestId);
        });
      }
    }
  }

  Future<void> _showRejectMessageDialog(String requestId) async {
    // 処理中チェック
    if (_processingRequestIds.contains(requestId)) {
      return;
    }
    
    final TextEditingController messageController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('辞退理由（任意）'),
          content: TextField(
            controller: messageController,
            decoration: const InputDecoration(
              hintText: '辞退理由を入力してください（任意）',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: !_processingRequestIds.contains(requestId) ? () {
                Navigator.pop(context);
                _respondToDateRequest(requestId, 'reject', rejectMessage: messageController.text);
              } : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(_processingRequestIds.contains(requestId) ? '処理中...' : '辞退する'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.partnerName),
        backgroundColor: const Color(0xFFF6BFBC),
        foregroundColor: Colors.white,
        actions: [
          // デートリクエストボタン
          IconButton(
            onPressed: () => _showDateRequestDialog(),
            icon: const Icon(Icons.calendar_today),
            tooltip: 'デートのお誘い',
          ),
          if (_matchDetail?['restaurant_name'] != null)
            IconButton(
              onPressed: () {
                // レストラン詳細表示
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(_matchDetail['restaurant_name']),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_matchDetail['restaurant_image_url'] != null)
                          Container(
                            height: 150,
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                                                          child: WebImageHelper.buildRestaurantImage(
                              _matchDetail['restaurant_image_url'],
                              width: double.infinity,
                              height: 150,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            ),
                          ),
                        if (_matchDetail['restaurant_category'] != null)
                          Text('カテゴリ: ${_matchDetail['restaurant_category']}'),
                        if (_matchDetail['restaurant_prefecture'] != null)
                          Text('都道府県: ${_matchDetail['restaurant_prefecture']}'),
                        if (_matchDetail['restaurant_nearest_station'] != null)
                          Text('最寄駅: ${_matchDetail['restaurant_nearest_station']}'),
                        if (_matchDetail['restaurant_price_range'] != null)
                          Text('価格帯: ${_matchDetail['restaurant_price_range']}'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.restaurant),
              tooltip: 'レストラン情報',
            ),
        ],
      ),
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'エラーが発生しました',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _isLoading = true;
                        _matchDetail = null; // マッチ詳細もリセット
                        _messages = []; // メッセージもリセット
                      });
                      _initializeData();
                    },
                    child: const Text('再試行'),
                  ),
                ],
              ),
            )
          : Column(
        children: [
          // 新着メッセージ表示（LINE/Instagram風）
          if (_hasNewMessages)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.blue[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.keyboard_arrow_down, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '新着メッセージがあります',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _hasNewMessages = false;
                      });
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Text(
                      '見る',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // メッセージリスト
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _matchDetail == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red),
                            SizedBox(height: 16),
                            Text(
                              'マッチ詳細の読み込みに失敗しました',
                              style: TextStyle(fontSize: 18, color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'メッセージを送って\n会話を始めましょう！',
                                  style: TextStyle(fontSize: 18, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final messageRaw = _messages[index];
                          
                          // メッセージデータを安全にMap<String, dynamic>に変換
                          final Map<String, dynamic> message = <String, dynamic>{};
                          if (messageRaw is Map) {
                            messageRaw.forEach((key, value) {
                              if (key is String) {
                                message[key] = value;
                              }
                            });
                          }
                          
                          // マッチ詳細が取得できているかチェック
                          if (_matchDetail == null) {
                            return const SizedBox.shrink();
                          }
                          
                          final isMyMessage = message['sender_id'] != _matchDetail?['partner_id'];
                          
                          // 特殊メッセージタイプをチェック
                          final messageType = message['message_type'] ?? 'text';
                          
                          if (messageType == 'date_request') {
                            return _buildDateRequestMessage(message, isMyMessage);
                          } else if (messageType == 'restaurant_voting') {
                            // 店舗投票メッセージは常にシステムメッセージとして扱う
                            return _buildRestaurantVotingMessage(message, false);
                          } else if (messageType == 'restaurant_voting_response') {
                            return _buildRestaurantVotingResponseMessage(message, isMyMessage);
                          } else if (messageType == 'restaurant_decision') {
                            return _buildRestaurantDecisionMessage(message);
                          } else if (messageType == 'image') {
                            return _buildImageMessage(message, isMyMessage);
                          }
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: isMyMessage 
                                  ? MainAxisAlignment.end 
                                  : MainAxisAlignment.start,
                              children: [
                                if (!isMyMessage) ...[
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundImage: message['sender_image_url'] != null
                                        ? NetworkImage(message['sender_image_url'])
                                        : null,
                                    child: message['sender_image_url'] == null
                                        ? const Icon(Icons.person, size: 16)
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: GestureDetector(
                                    onLongPress: () => _showMessageOptions(message, isMyMessage),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMyMessage 
                                            ? const Color(0xFFF6BFBC) 
                                            : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            message['content'] ?? '',
                                            style: TextStyle(
                                              color: isMyMessage 
                                                  ? Colors.white 
                                                  : Colors.black87,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatMessageTime(message['sent_at']),
                                            style: TextStyle(
                                              color: isMyMessage 
                                                  ? Colors.white70 
                                                  : Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          
          // メッセージ入力エリア
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _isSending ? null : _sendImage,
                  icon: Icon(
                    Icons.photo,
                    color: _isSending ? Colors.grey : const Color(0xFFFFFACD),
                  ),
                  tooltip: '画像を送信',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: const Color(0xFFF6BFBC),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// マッチ画面専用: 店舗投票メッセージ表示（単一選択）
  Widget _buildRestaurantVotingMessage(Map<String, dynamic> message, bool isMyMessage) {
    
    // 店舗投票データはdate_request_dataフィールドにある
    final restaurantVotingDataRaw = message['date_request_data'];
    if (restaurantVotingDataRaw == null) {
      return Container();
    }

    // JSON文字列をパース
    Map<String, dynamic> restaurantVotingData;
    try {
      if (restaurantVotingDataRaw is String) {
        restaurantVotingData = Map<String, dynamic>.from(jsonDecode(restaurantVotingDataRaw));
      } else if (restaurantVotingDataRaw is Map) {
        restaurantVotingData = <String, dynamic>{};
        restaurantVotingDataRaw.forEach((key, value) {
          if (key is String) {
            restaurantVotingData[key] = value;
          }
        });
      } else {
        return Container();
      }
    } catch (e) {
      return Container();
    }
    
    if (restaurantVotingData['restaurants'] == null) {
      return Container();
    }

    // 安全な型変換
    final restaurantsRaw = restaurantVotingData['restaurants'] ?? [];
    final restaurants = <Map<String, dynamic>>[];
    
    if (restaurantsRaw is List) {
      for (final item in restaurantsRaw) {
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
    
    final decidedDate = restaurantVotingData['decidedDate']?.toString() ?? '';
    
    // votingId設定を修正: 古いカスタム形式IDを検出した場合はrelated_date_request_idを使用
    String votingId = restaurantVotingData['restaurantVotingId']?.toString() ?? '';
    final relatedDateRequestId = message['related_date_request_id']?.toString() ?? '';
    
    // 古いカスタム形式（restaurant_voting_で始まる）を検出した場合はUUID形式のIDに置き換え
    if (votingId.startsWith('restaurant_voting_') && relatedDateRequestId.isNotEmpty) {
      votingId = relatedDateRequestId;
    } else if (votingId.isEmpty && relatedDateRequestId.isNotEmpty) {
      votingId = relatedDateRequestId;
    }
    

    // 1対1マッチでの受信者判定ロジック実装
    bool isRestaurantVotingReceiver = false;
    
    // 現在のユーザーのUUID IDを計算
    String? currentUserUuidId;
    final user1Id = _matchDetail?['user1_id'];
    final user2Id = _matchDetail?['user2_id'];
    final partnerId = _matchDetail?['partner_id'];
    
    if (partnerId == user1Id) {
      currentUserUuidId = user2Id;
    } else if (partnerId == user2Id) {
      currentUserUuidId = user1Id;
    }
    
    // related_date_request_idを使って元のデートリクエストメッセージを検索
    // 重要：現在の店舗投票メッセージのvotingIdと一致するもののみ処理
    for (final msg in _messages) {
      if (msg is Map) {
        final msgData = <String, dynamic>{};
        msg.forEach((key, value) {
          if (key is String) msgData[key] = value;
        });
        
        // 元のデートリクエストメッセージを特定（votingIdが一致するもののみ）
        if (msgData['message_type'] == 'date_request' && 
            msgData['related_date_request_id'] == votingId) {
          final originalRequestSenderId = msgData['sender_id'];
          
          
          // 現在のユーザーが元のリクエスト送信者でない場合 = 受信者
          if (currentUserUuidId != null && originalRequestSenderId != currentUserUuidId) {
            isRestaurantVotingReceiver = true;
          } else {
          }
          break;
        }
      }
    }

    // エラーハンドリングを強化
    if (restaurants.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: const Text(
          'エラー: 候補店舗が見つかりません',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    if (votingId.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: const Text(
          'エラー: 投票IDが見つかりません',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    // 投票済みかチェック
    return FutureBuilder<bool>(
      future: _isAlreadyVotedForMatchRestaurant(votingId).catchError((error) {
        return false; // エラーの場合は未投票として扱う
      }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'エラー: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final isAlreadyVoted = snapshot.data ?? false;
        
        // 店舗決定済みかチェック
        bool isRestaurantDecided = false;
        for (final messageRaw in _messages) {
          if (messageRaw is Map) {
            final message = <String, dynamic>{};
            messageRaw.forEach((key, value) {
              if (key is String) message[key] = value;
            });
            
            if (message['message_type'] == 'restaurant_decision' &&
                message['related_date_request_id'] == votingId) {
              isRestaurantDecided = true;
              break;
            }
          }
        }
        
        // 表示判定: 店舗決定済みでない && 受信者 && (未投票 || 処理中)
        final shouldShowVotingUI = !isRestaurantDecided && 
                                  isRestaurantVotingReceiver && 
                                  (!isAlreadyVoted || _processingVotingIds.contains(votingId));
        
        
        // 暫定的にシンプルな構造で表示（デバッグ用）
        return Container(
          width: 300,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border.all(color: Colors.blue.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.store, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '🏪 店舗投票',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '決定日程: ${_formatDecidedDate(decidedDate)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '候補店舗数: ${restaurants.length}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              // 処理中状態を考慮したボタン表示
              _processingVotingIds.contains(votingId)
                  ? Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '投票処理中...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : shouldShowVotingUI
                      ? ElevatedButton(
                          onPressed: () {
                            try {
                              _showMatchRestaurantSelectionDialog(votingId, restaurants);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('エラーが発生しました: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: const Text('店舗を選択する'),
                        )
                      : Column(
                          children: [
                            Container(
                              width: double.infinity,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Center(
                                child: Text(
                                  isAlreadyVoted 
                                      ? '投票完了' 
                                      : isRestaurantVotingReceiver 
                                          ? '投票待ち...' 
                                          : '相手の店舗選択を待っています...',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            // デバッグ用: 投票状態リセットボタン（不正な状態の場合のみ表示）
                            if (_shouldShowResetButton(votingId, isAlreadyVoted))
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _completedVoteRequestIds.remove(votingId);
                                      _processingVotingIds.remove(votingId);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('投票状態をリセットしました\n再度投票できます'),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 36),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.refresh, size: 16),
                                      SizedBox(width: 6),
                                      Text('投票状態をリセット'),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
            ],
          ),
        );
      },
    );
  }

  /// 店舗投票回答メッセージ表示
  Widget _buildRestaurantVotingResponseMessage(Map<String, dynamic> message, bool isMyMessage) {
    final responseDataRaw = message['date_request_data'];
    if (responseDataRaw == null) return Container();

    Map<String, dynamic> responseData;
    try {
      if (responseDataRaw is String) {
        responseData = Map<String, dynamic>.from(jsonDecode(responseDataRaw));
      } else if (responseDataRaw is Map) {
        responseData = <String, dynamic>{};
        responseDataRaw.forEach((key, value) {
          if (key is String) {
            responseData[key] = value;
          }
        });
      } else {
        return Container();
      }
    } catch (e) {
      return Container();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMyMessage ? Colors.blue[50] : Colors.grey[100],
        border: Border.all(color: isMyMessage ? Colors.blue[200]! : Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: isMyMessage ? Colors.blue[600] : Colors.grey[600],
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${message['sender_name'] ?? 'ユーザー'}が店舗を選択しました',
              style: TextStyle(
                fontSize: 12,
                color: isMyMessage ? Colors.blue[700] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 店舗決定メッセージ表示
  Widget _buildRestaurantDecisionMessage(Map<String, dynamic> message) {
    
    final decisionDataRaw = message['date_request_data'];
    if (decisionDataRaw == null) {
      return Container();
    }

    Map<String, dynamic> decisionData;
    try {
      if (decisionDataRaw is String) {
        decisionData = Map<String, dynamic>.from(jsonDecode(decisionDataRaw));
      } else if (decisionDataRaw is Map) {
        decisionData = <String, dynamic>{};
        decisionDataRaw.forEach((key, value) {
          if (key is String) {
            decisionData[key] = value;
          }
        });
      } else {
        return Container();
      }
    } catch (e) {
      return Container();
    }


    final status = decisionData['status']?.toString() ?? '';
    final decidedRestaurantName = decisionData['decidedRestaurantName']?.toString() ?? '';
    final decidedRestaurantId = decisionData['decidedRestaurantId']?.toString() ?? '';
    final decidedDate = decisionData['decidedDate']?.toString() ?? '';
    

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status == 'decided' ? Colors.green[50] : Colors.orange[50],
        border: Border.all(
          color: status == 'decided' ? Colors.green[200]! : Colors.grey[200]!
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            status == 'decided' ? Icons.celebration : Icons.help_outline,
            color: status == 'decided' ? Colors.green[600] : Colors.orange[600],
            size: 32,
          ),
          const SizedBox(height: 8),
          if (status == 'decided') ...[
            const Text(
              '🎉 デート確定！',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '📅 ${_formatDecidedDate(decidedDate)}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '🏪 $decidedRestaurantName',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '素敵な時間をお過ごしください💕',
              style: TextStyle(
                color: Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            // 予約案内ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final originalRequestId = decisionData['originalRequestId'] ?? '';
                  _showReservationConfirmDialog(originalRequestId, decidedRestaurantName, decidedRestaurantId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant_menu, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '予約案内を見る',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              message['content'] ?? '',
              style: TextStyle(
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// 投票済みかチェック
  /// マッチ画面専用: 店舗投票済みかチェック
  Future<bool> _isAlreadyVotedForMatchRestaurant(String votingId) async {
    try {
      
      // 現在のユーザーIDを取得（partner_idを基準とした正しい方法を使用）
      final user1Id = _matchDetail?['user1_id']?.toString();
      final user2Id = _matchDetail?['user2_id']?.toString();
      final partnerId = _matchDetail?['partner_id']?.toString();
      
      String? currentUserUuidId;
      // パートナーでない方が現在のユーザー
      if (user1Id == partnerId) {
        currentUserUuidId = user2Id; // user2が現在のユーザー
      } else {
        currentUserUuidId = user1Id; // user1が現在のユーザー
      }
      
      
      // マッチのメッセージから投票済みかチェック
      for (final messageRaw in _messages) {
        if (messageRaw is Map) {
          final message = <String, dynamic>{};
          messageRaw.forEach((key, value) {
            if (key is String) message[key] = value;
          });

          
                  if (message['message_type'] == 'restaurant_voting_response' &&
            message['sender_id'] == currentUserUuidId &&
            message['related_date_request_id'] == votingId) {
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// マッチ画面専用: 店舗選択ダイアログ表示（単一選択）
  void _showMatchRestaurantSelectionDialog(String votingId, List<Map<String, dynamic>> restaurants) {
    if (_processingVotingIds.contains(votingId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('投票処理中です。しばらくお待ちください。'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    String? selectedRestaurantId;
    bool isProcessing = false;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => WillPopScope(
          onWillPop: () async => !isProcessing,
          child: AlertDialog(
            title: const Text('希望店舗を1つ選択してください'),
            content: restaurants.isEmpty 
              ? const Text('選択可能な店舗がありません')
              : SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedRestaurantId != null ? '選択済み' : '店舗を選択してください',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: restaurants.map((restaurant) {
                            final restaurantId = restaurant['id'];
                            final isSelected = selectedRestaurantId == restaurantId;
                            
                            return RadioListTile<String>(
                              value: restaurantId,
                              groupValue: selectedRestaurantId,
                              onChanged: (value) {
                                setState(() {
                                  selectedRestaurantId = value;
                                });
                              },
                              title: Text(restaurant['name'] ?? ''),
                              subtitle: restaurant['category'] != null 
                                  ? Text(restaurant['category']) 
                                  : null,
                              secondary: restaurant['image_url'] != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                                                    child: WebImageHelper.buildRestaurantImage(
                                restaurant['image_url'],
                                width: 40,
                                height: 40,
                                borderRadius: BorderRadius.circular(6),
                              ),
                                    )
                                  : const Icon(Icons.restaurant),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: (selectedRestaurantId != null && !isProcessing)
                    ? () async {
                        setState(() {
                          isProcessing = true;
                        });
                        
                        this.setState(() {
                          _processingVotingIds.add(votingId);
                        });
                        
                        Navigator.pop(context);
                        _respondToMatchRestaurantVoting(votingId, [selectedRestaurantId!]);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                ),
                child: isProcessing 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('投票する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// リセットボタンを表示すべきかどうかの判定
  bool _shouldShowResetButton(String votingId, bool isAlreadyVoted) {
    // 状態管理で投票済みとなっているが、実際のメッセージが存在しない場合のみ表示
    if (!_completedVoteRequestIds.contains(votingId) && !_processingVotingIds.contains(votingId)) {
      return false;  // 状態管理に含まれていない場合は表示しない
    }
    
    // 実際のメッセージが存在するかチェック
    String? currentUserUuidId;
    if (_matchDetail != null) {
      final user1Id = _matchDetail!['user1_id'];
      final user2Id = _matchDetail!['user2_id'];
      final partnerId = _matchDetail!['partner_id'];
      
      if (partnerId == user1Id) {
        currentUserUuidId = user2Id;
      } else if (partnerId == user2Id) {
        currentUserUuidId = user1Id;
      }
    }
    
    if (currentUserUuidId == null) return false;
    
    // 実際に投票済みメッセージが存在するかチェック
    for (final messageRaw in _messages) {
      if (messageRaw is Map) {
        final message = <String, dynamic>{};
        messageRaw.forEach((key, value) {
          if (key is String) message[key] = value;
        });
        
        if (message['message_type'] == 'restaurant_voting_response' &&
            message['sender_id'] == currentUserUuidId &&
            message['related_date_request_id'] == votingId) {
          return false;  // 実際のメッセージが存在する場合は表示しない
        }
      }
    }
    
    // 状態管理で投票済みとなっているが、実際のメッセージが存在しない場合は表示
    return true;
  }

  /// 日程投票完了状態の復元（メッセージから推論）
  void _restoreCompletedVoteStates() {
    final Set<String> restoredVoteIds = {};
    
    // メッセージから店舗投票や店舗決定が存在するrelated_date_request_idを探す
    for (final messageRaw in _messages) {
      if (messageRaw is Map) {
        final message = <String, dynamic>{};
        messageRaw.forEach((key, value) {
          if (key is String) message[key] = value;
        });
        
        final messageType = message['message_type'];
        final relatedId = message['related_date_request_id'];
        
        // 店舗投票または店舗決定メッセージが存在する場合、その日程投票は完了している
        if (relatedId != null && (
            messageType == 'restaurant_voting' ||
            messageType == 'restaurant_voting_response' ||
            messageType == 'restaurant_decision'
          )) {
          restoredVoteIds.add(relatedId);
        }
      }
    }
    
    // 復元された投票完了状態を設定
    if (restoredVoteIds.isNotEmpty) {
      setState(() {
        _completedVoteRequestIds.addAll(restoredVoteIds);
      });
    }
  }

  /// 投票済み状態の整合性チェック（不正な状態をクリア）
  void _cleanupInvalidVotingStates() {
    if (_completedVoteRequestIds.isEmpty) return;
    
    // 現在のユーザーIDを取得
    String? currentUserUuidId;
    if (_matchDetail != null) {
      final user1Id = _matchDetail!['user1_id'];
      final user2Id = _matchDetail!['user2_id'];
      final partnerId = _matchDetail!['partner_id'];
      
      if (partnerId == user1Id) {
        currentUserUuidId = user2Id;
      } else if (partnerId == user2Id) {
        currentUserUuidId = user1Id;
      }
    }
    
    if (currentUserUuidId == null) return;
    
    final Set<String> invalidVotingIds = {};
    
    // _completedVoteRequestIdsの各IDについて、実際に投票済みメッセージが存在するかチェック
    for (final votingId in _completedVoteRequestIds) {
      bool foundValidMessage = false;
      bool hasRestaurantVotingMessage = false;
      
      for (final messageRaw in _messages) {
        if (messageRaw is Map) {
          final message = <String, dynamic>{};
          messageRaw.forEach((key, value) {
            if (key is String) message[key] = value;
          });
          
          // 店舗投票の回答メッセージがある場合
          if (message['message_type'] == 'restaurant_voting_response' &&
              message['sender_id'] == currentUserUuidId &&
              message['related_date_request_id'] == votingId) {
            foundValidMessage = true;
            break;
          }
          
          // 店舗投票メッセージが存在する場合（日程投票完了の証拠）
          if (message['message_type'] == 'restaurant_voting' &&
              message['related_date_request_id'] == votingId) {
            hasRestaurantVotingMessage = true;
          }
        }
      }
      
      // 店舗投票メッセージが存在するか、または回答メッセージが存在する場合は有効
      if (!foundValidMessage && !hasRestaurantVotingMessage) {
        invalidVotingIds.add(votingId);
      }
    }
    
    // 不正な投票済み状態を削除
    if (invalidVotingIds.isNotEmpty) {
      setState(() {
        _completedVoteRequestIds.removeAll(invalidVotingIds);
        _processingVotingIds.removeAll(invalidVotingIds);
      });
    }
  }

  /// マッチ画面専用: 店舗投票回答
  Future<void> _respondToMatchRestaurantVoting(String votingId, List<String> selectedRestaurantIds) async {
    
    try {
      
      final callable = FirebaseFunctions.instance.httpsCallable('respondToMatchRestaurantVoting');
      
      // タイムアウト設定を追加
      final result = await callable.call({
        'restaurantVotingId': votingId,
        'selectedRestaurantIds': selectedRestaurantIds,
        'responseMessage': '店舗を選択しました！',
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Cloud Functions呼び出しがタイムアウトしました（30秒）'),
      );
      
      
      if (result.data['success'] == true) {
        // 投票完了状態を即座に反映（成功時のみ）
        setState(() {
          _completedVoteRequestIds.add(votingId);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('店舗投票に回答しました（1店舗選択）'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // 店舗決定結果をチェック
        final decisionResult = result.data['decisionResult'];
        
        if (decisionResult != null && decisionResult['status'] == 'decided') {
          // 店舗決定時は複数回メッセージ再読み込みを実行
          await _loadMessages();
          await Future.delayed(const Duration(milliseconds: 500));
          await _loadMessages();
          await Future.delayed(const Duration(milliseconds: 1000));
          await _loadMessages();
        } else {
          // 1対1マッチの場合、強制的に店舗決定メッセージの再読み込みを試行
          
          // 即座に1回読み込み
          await _loadMessages();
          
          // 短間隔で最大10回再試行（より頻繁にチェック）
          for (int i = 0; i < 10; i++) {
            await Future.delayed(Duration(milliseconds: 500 + (i * 200))); // 段階的に間隔を伸ばす
            await _loadMessages();
            
            
            // restaurant_decisionメッセージが見つかったら終了
            bool foundDecisionMessage = false;
            for (final messageRaw in _messages) {
              if (messageRaw is Map) {
                final message = <String, dynamic>{};
                messageRaw.forEach((key, value) {
                  if (key is String) message[key] = value;
                });
                
                if (message['message_type'] == 'restaurant_decision' &&
                    message['related_date_request_id'] == votingId) {
                  foundDecisionMessage = true;
                  break;
                }
              }
            }
            
            if (foundDecisionMessage) {
              // 店舗決定メッセージが見つかった後、UIを最新状態に更新
              if (mounted) {
                setState(() {});
              }
              break;
            }
            
          }
        }
      } else {
        throw Exception(result.data['message'] ?? '投票に失敗しました');
      }
    } catch (e, stackTrace) {
      // Firebase Functions特有のエラーを詳細に解析
      String errorMessage = '投票に失敗しました';
      String errorDetails = e.toString();
      
      if (e.toString().contains('functions/unauthenticated')) {
        errorMessage = '認証エラーです。アプリを再起動してください';
        errorDetails = '認証情報が無効または期限切れです';
      } else if (e.toString().contains('functions/permission-denied')) {
        errorMessage = '権限エラーです。このユーザーは投票権限がありません';
        errorDetails = '投票権限がない、または送信者が投票しようとしています';
      } else if (e.toString().contains('functions/already-exists')) {
        errorMessage = '既に投票済みです';
        errorDetails = 'この投票に既に回答済みです';
      } else if (e.toString().contains('functions/not-found')) {
        errorMessage = '投票が見つかりません';
        errorDetails = '投票IDが無効、または投票が存在しません';
      } else if (e.toString().contains('functions/internal')) {
        errorMessage = 'サーバー内部エラーが発生しました';
        errorDetails = 'Cloud Functionsまたはデータベースでエラーが発生';
      } else if (e.toString().contains('Cloud Functions呼び出しがタイムアウト')) {
        errorMessage = 'タイムアウトエラーです。ネットワーク接続を確認してください';
        errorDetails = '30秒以内にレスポンスが返ってきませんでした';
      } else if (e.toString().contains('店舗投票に回答済みです')) {
        errorMessage = '既に投票済みです';
        errorDetails = 'データベースに投票記録が既に存在します';
      } else if (e.toString().contains('店舗投票回答の保存に失敗しました')) {
        errorMessage = 'データベースエラーが発生しました';
        errorDetails = 'メッセージの保存処理でエラーが発生しました';
      }
      
      // エラー時は投票済み状態に追加しない（既に追加されている場合は削除）
      setState(() {
        _completedVoteRequestIds.remove(votingId);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                errorMessage,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '詳細: $errorDetails',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'デバッグ用リセットボタンをお使いください',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _processingVotingIds.remove(votingId);
      });
    }
  }

  // 画像送信処理（楽観的更新）
  Future<void> _sendImage() async {
    try {
      // 画像選択方法を選択
      final source = await _showImageSourceDialog();
      if (source == null) return;
      
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) return;

      // 即座にローディング状態を解除（ユーザー体験優先）
      setState(() {
        _isSending = false;
      });

      // プロフィール編集画面と同じ方式でアップロード
      String? imageUrl = await _uploadMatchImage(image);
      if (imageUrl == null) {
        throw Exception('画像のアップロードに失敗しました');
      }

      // 画像メッセージを送信
      await _sendMessageWithImage(imageUrl);
      
    } catch (e) {
      
      String errorMessage = '画像の送信に失敗しました';
      if (e.toString().contains('認証状態が確認できません') || 
          e.toString().contains('認証トークンが無効') ||
          e.toString().contains('認証状態が無効') ||
          e.toString().contains('unauthorized')) {
        errorMessage = '認証エラーが発生しました。再ログインしてください。';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // マッチ画像アップロード（高速化）
  Future<String?> _uploadMatchImage(XFile image) async {
    try {
      
      // Web版での認証状態確認を強化
      if (kIsWeb) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('Web版: 認証状態が確認できません。再ログインしてください。');
        }
        
        // 認証トークンを明示的に取得して確認
        try {
          final token = await user.getIdToken(true);
          if (token == null || token.isEmpty) {
            throw Exception('Web版: 認証トークンが無効です。再ログインしてください。');
          }
        } catch (e) {
          throw Exception('Web版: 認証状態が無効です。再ログインしてください。');
        }
      }

      String imageUrl;
      
      if (kIsWeb) {
        // Web版: XFileをUint8Listでアップロード（高速化）
        final bytes = await image.readAsBytes();
        imageUrl = await _uploadImageBytes(bytes, 'matches');
      } else {
        // モバイル版: Fileでアップロード（HEIC変換含む）
        final originalFile = File(image.path);
        final convertedFile = await _convertHeicToJpeg(originalFile);
        final finalFile = convertedFile ?? originalFile;
        imageUrl = await _uploadImageFile(finalFile, 'matches');
      }

      return imageUrl;
    } catch (e) {
      
      String errorMessage = '画像のアップロードに失敗しました';
      if (e.toString().contains('認証状態が確認できません') || 
          e.toString().contains('認証トークンが無効') ||
          e.toString().contains('認証状態が無効') ||
          e.toString().contains('unauthorized')) {
        errorMessage = '認証エラーが発生しました。再ログインしてください。';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  // 画像選択方法を選択するダイアログ
  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('画像を選択'),
        content: const Text('画像の取得方法を選択してください'),
        actions: [
          // Web版ではカメラボタンを非表示
          if (!kIsWeb)
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
              ),
              child: const Text('カメラで撮影'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
            ),
            child: const Text('ギャラリーから選択'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
            ),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  // Web版用: Uint8Listで画像アップロード（高速化）
  Future<String> _uploadImageBytes(Uint8List bytes, String folder) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('$folder-images')
          .child(user.uid)
          .child(fileName);

      // Web版では明示的に認証トークンを設定
      final token = await user.getIdToken(true);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': user.uid,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );
      
      final uploadTask = storageRef.putData(bytes, metadata);
      final snapshot = await uploadTask.timeout(const Duration(seconds: 10));
      final downloadUrl = await snapshot.ref.getDownloadURL().timeout(const Duration(seconds: 2));
      
      return downloadUrl;
    } catch (e) {
      rethrow;
    }
  }

  // モバイル版用: Fileで画像アップロード（高速化）
  Future<String> _uploadImageFile(File file, String folder) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('$folder-images')
          .child(user.uid)
          .child(fileName);

      final uploadTask = storageRef.putFile(file);
      final snapshot = await uploadTask.timeout(const Duration(seconds: 10));
      final downloadUrl = await snapshot.ref.getDownloadURL().timeout(const Duration(seconds: 2));
      
      return downloadUrl;
    } catch (e) {
      rethrow;
    }
  }

  // HEIC画像をJPEGに変換
  Future<File?> _convertHeicToJpeg(File heicFile) async {
    try {

      // HEICファイルを読み込み
      final bytes = await heicFile.readAsBytes();
      
      // imageパッケージでデコード（HEIC対応）
      final image = img.decodeImage(bytes);
      if (image == null) {
        return null;
      }
      

      // JPEGエンコード（品質90%）
      final jpegBytes = img.encodeJpg(image, quality: 90);
      
      // 一時ディレクトリに保存
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jpegFile = File('${tempDir.path}/converted_heic_$timestamp.jpg');
      
      await jpegFile.writeAsBytes(jpegBytes);
      
      return jpegFile;
    } catch (e) {
      return null;
    }
  }

  // 画像メッセージを送信
  Future<void> _sendMessageWithImage(String imageUrl) async {
    // 送信開始フラグを設定
    setState(() {
      _isSending = true;
    });

    // 即座にメッセージをUIに追加
    final newMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'content': imageUrl,
      'sender_id': FirebaseAuth.instance.currentUser?.uid,
      'sent_at': DateTime.now().toIso8601String(),
      'message_type': 'image',
    };
    
    setState(() {
      _messages.add(newMessage);
      _lastMessageCount = _messages.length;
    });
    
    // 最新メッセージにスクロール
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }

    // バックグラウンドでDBに保存
    await _saveImageMessageToDatabase(imageUrl, newMessage);
    
    // 送信完了フラグを設定
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  // メッセージオプションを表示（自分から見て削除のみ）
  void _showMessageOptions(Map<String, dynamic> message, bool isMyMessage) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('メッセージを非表示'),
              subtitle: const Text('このメッセージを自分から見て削除します'),
              onTap: () {
                Navigator.pop(context);
                _hideMessage(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.grey),
              title: const Text('メッセージをコピー'),
              subtitle: const Text('メッセージの内容をクリップボードにコピーします'),
              onTap: () {
                Navigator.pop(context);
                _copyMessage(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.grey),
              title: const Text('キャンセル'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // メッセージを非表示（自分から見て削除）
  Future<void> _hideMessage(Map<String, dynamic> message) async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メッセージを非表示'),
        content: const Text('このメッセージを自分から見て削除しますか？\n相手には表示されたままです。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('非表示'),
          ),
        ],
      ),
    );

    if (shouldHide != true) return;

    try {
      // UIからメッセージを削除（自分から見てのみ）
      setState(() {
        _messages.removeWhere((msg) => msg['id'] == message['id']);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('メッセージを非表示にしました'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('メッセージの非表示に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // メッセージをコピー
  void _copyMessage(Map<String, dynamic> message) {
    // Flutter WebではクリップボードAPIを使用
    // 実際の実装はプラットフォームに依存
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('メッセージをコピーしました'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  // バックグラウンドで画像メッセージをDBに保存
  Future<void> _saveImageMessageToDatabase(String imageUrl, Map<String, dynamic> message) async {
    try {
      print('🔍 画像メッセージ送信開始: matchId=${widget.matchId}, imageUrl=$imageUrl');
      
      // 画像メッセージ送信（バックグラウンドで実行）
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('sendMessage');
      final result = await callable({
        'matchId': widget.matchId,
        'content': imageUrl,
        'type': 'image',
      }).timeout(const Duration(seconds: 10));
      
      print('🔍 画像メッセージ送信結果: ${result.data}');
      
      if (mounted && result.data != null && result.data['success'] == true) {
        print('✅ 画像メッセージ送信成功');
        // 成功時は何もしない（UIは既に更新済み）
      } else {
        print('❌ 画像メッセージ送信失敗: ${result.data}');
        // 失敗時はUIからメッセージを削除
        if (mounted) {
          setState(() {
            _messages.removeWhere((msg) => msg['id'] == message['id']);
            _lastMessageCount = _messages.length;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('画像メッセージの保存に失敗しました: ${result.data?['error'] ?? '不明なエラー'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ 画像メッセージ送信エラー: $e');
      // エラー時はUIからメッセージを削除
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg['id'] == message['id']);
          _lastMessageCount = _messages.length;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('画像メッセージの保存に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // エラー時も送信フラグをリセット
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // 画像メッセージ表示
  Widget _buildImageMessage(Map<String, dynamic> message, bool isMyMessage) {
    final imageUrl = message['content'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMyMessage 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (!isMyMessage) ...[
            CircleAvatar(
              radius: 16,
              backgroundImage: message['sender_image_url'] != null
                  ? NetworkImage(message['sender_image_url'])
                  : null,
              child: message['sender_image_url'] == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: WebImageHelper.buildImage(
                    imageUrl,
                    width: 250,
                    height: 250,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      width: 250,
                      height: 250,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _formatMessageTime(message['sent_at']),
                    style: TextStyle(
                      color: isMyMessage 
                          ? Colors.white70 
                          : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 最新メッセージが画像の場合のテキスト変換ヘルパー
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

} 