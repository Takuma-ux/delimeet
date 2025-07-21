import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/group_model.dart';
import '../services/group_service.dart';
import '../services/chat_image_provider.dart';
import 'group_member_search_page.dart';
import 'profile_view_page.dart';
import '../pages/send_group_date_request_page.dart';
import '../models/group_date_request_model.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'group_join_requests_page.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/web_image_helper.dart';

class GroupChatPage extends StatefulWidget {
  final Group group;

  const GroupChatPage({
    super.key,
    required this.group,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GroupService _groupService = GroupService();
  
  bool _isSending = false;
  
  // 新着メッセージ管理（LINE/Instagram風）
  bool _hasNewMessages = false;
  int _lastMessageCount = 0;
  
  // ユーザー情報キャッシュ
  final Map<String, Map<String, dynamic>> _userCache = {};
  
  // 日程投票処理中のリクエストIDを管理
  final Set<String> _processingRequestIds = {};
  
  // 店舗投票処理中のvotingIDを管理
  final Set<String> _processingVotingIds = {};
  
  // 投票完了済みのvotingIDを管理（ローカル状態）
  final Set<String> _completedVotingIds = {};
  
  // いいね状態を管理
  Set<String> _likedUsers = {};
  bool _likesLoaded = false;
  
  // 画像読み込み状態を管理（点滅防止用）
  bool _imagesInitialized = false;

  @override
  void initState() {
    super.initState();
    // 初期化を遅延実行して画面の点滅を防ぐ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserLikes();
      // 画像初期化完了をマーク
      setState(() {
        _imagesInitialized = true;
      });
    });
  }

  // いいね状態を取得
  Future<void> _loadUserLikes() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getUserLikes');
      final result = await callable().timeout(const Duration(seconds: 10));
      
      if (mounted) {
        // 点滅を防ぐため、一度だけsetStateを実行
        final sentLikes = List.from(result.data['sentLikes'] ?? []);
        
        // いいね済みユーザーIDを正確に取得
        final newLikedUsers = <String>{};
        for (int i = 0; i < sentLikes.length; i++) {
          final like = sentLikes[i];
          
          // liked_user_idフィールドを優先的に使用
          String? userId = like['liked_user_id']?.toString();
          if (userId != null && userId.isNotEmpty) {
            newLikedUsers.add(userId);
            continue;
          }
          
          // フォールバックとして他のフィールドも確認
          final possibleIds = [
            like['id']?.toString(),
            like['user_id']?.toString(),
          ].where((id) => id != null && id.isNotEmpty);
          
          for (final id in possibleIds) {
            newLikedUsers.add(id!);
          }
        }
        
        setState(() {
          _likedUsers = newLikedUsers;
          _likesLoaded = true;
        });
      }
    } catch (e) {
      // エラー時は初期化して処理を続行
      if (mounted) {
        setState(() {
          _likedUsers = {};
          _likesLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 価格帯表示ヘルパー（チャット用）
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

  /// 場所表示ヘルパー（チャット用）
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

  /// ユーザー情報を取得（キャッシュ機能付き）
  Future<Map<String, dynamic>?> _getUserInfo(String userId) async {
    // キャッシュから取得
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }

    try {
      // Cloud Functionで検索
      final callable = FirebaseFunctions.instance.httpsCallable('searchUsers');
      final result = await callable.call({
        'firebase_uid': userId,
      });
      
      if (result.data != null && result.data['exists'] == true) {
        final userInfo = {
          'name': result.data['user']['name'] ?? 'ユーザー',
          'image_url': result.data['user']['image_url'],
          'id': result.data['user']['id'], // UUIDを保存
        };
        _userCache[userId] = userInfo;
        return userInfo;
      } else {
        // Firestoreで直接検索（firebase_uidフィールドで検索）
        final usersQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('firebase_uid', isEqualTo: userId)
            .limit(1)
            .get();
        
        if (usersQuery.docs.isNotEmpty) {
          final userData = usersQuery.docs.first.data();
          final userInfo = {
            'name': userData['name'] ?? 'ユーザー',
            'image_url': userData['image_url'],
            'id': userData['id'], // UUIDを保存
          };
          _userCache[userId] = userInfo;
          return userInfo;
        }
      }
    } catch (e) {
    }
    
    return null;
  }

  /// プロフィール画面に遷移
  void _navigateToProfile(String? userUuid) {
    
    if (userUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ユーザー情報を取得できませんでした'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProfileViewPage(userId: userUuid),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('プロフィール画面の表示に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// デートリクエストダイアログを表示
  void _showDateRequestDialog() {
    // 管理者権限をチェック
    if (!widget.group.admins.contains(_groupService.currentUserId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('グループデートリクエストの作成は管理者のみ可能です'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SendGroupDateRequestPage(
          group: widget.group,
          memberIds: widget.group.members,
        ),
      ),
    ).then((result) {
      // デートリクエスト送信後にメッセージをリロード
      if (result == true) {
        // メッセージリストを更新するためにsetStateを呼ぶ
        setState(() {});
      }
    });
  }

  /// デートリクエスト回答
  Future<void> _respondToDateRequest(String requestId, String response, List<String> proposedDates) async {
    // 既に処理中の場合は何もしない（二重押し防止）
    if (_processingRequestIds.contains(requestId)) {
      return;
    }
    
    // 処理中状態に設定
    setState(() {
      _processingRequestIds.add(requestId);
    });
    
    try {
      if (response == 'accept') {
        // 承認の場合は日程選択ダイアログを表示
        _showDateSelectionDialog(requestId, proposedDates);
      } else {
        // 拒否の場合は直接処理
        await _sendDateResponse(requestId, response, '', '');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('処理に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      // 拒否の場合のみここで処理中状態を解除（承認の場合は_sendDateResponseで解除）
      if (response != 'accept') {
        setState(() {
          _processingRequestIds.remove(requestId);
        });
      }
    }
  }

  /// 日程選択ダイアログ表示
  void _showDateSelectionDialog(String requestId, List<String> proposedDates) {
    Set<DateTime> selectedDates = {};
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('希望日時を選択してください\n（複数選択可能）'),
          content: proposedDates.isEmpty 
            ? const Text('選択可能な日時がありません')
            : SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '選択済み: ${selectedDates.length}個',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: proposedDates.map((dateStr) {
                          try {
                            final date = DateTime.parse(dateStr);
                            final formattedDate = '${date.month}/${date.day}(${_getWeekday(date.weekday)}) ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                            
                            return CheckboxListTile(
                              title: Text(formattedDate),
                              value: selectedDates.contains(date),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    selectedDates.add(date);
                                  } else {
                                    selectedDates.remove(date);
                                  }
                                });
                              },
                              activeColor: Colors.green,
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          } catch (e) {
                            return Container();
                          }
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: selectedDates.isNotEmpty 
                ? () {
                    Navigator.pop(context);
                    final selectedDatesString = selectedDates
                        .map((date) => date.toIso8601String())
                        .join(',');
                    _sendDateResponse(requestId, 'accept', selectedDatesString, '');
                  }
                : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text('承認する (${selectedDates.length}個選択)'),
            ),
          ],
        ),
      ),
    );
  }

  /// 曜日取得ヘルパー
  String _getWeekday(int weekday) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return weekdays[weekday - 1];
  }

  // 開催日時をフォーマット
  String _formatEventDateTime(DateTime eventDateTime) {
    final month = eventDateTime.month.toString().padLeft(2, '0');
    final day = eventDateTime.day.toString().padLeft(2, '0');
    final hour = eventDateTime.hour.toString().padLeft(2, '0');
    final minute = eventDateTime.minute.toString().padLeft(2, '0');
    final weekday = _getWeekday(eventDateTime.weekday);
    
    return '$month/$day($weekday) $hour:$minute';
  }

  /// デートリクエスト回答送信
  Future<void> _sendDateResponse(String requestId, String response, String? selectedDate, String message) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('respondToGroupDateRequest');
      await callable.call({
        'requestId': requestId,
        'response': response,
        'responseMessage': message,
        'selectedDate': selectedDate,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response == 'accept' ? 'デートリクエストを承認しました' : 'デートリクエストを辞退しました'),
          backgroundColor: response == 'accept' ? Colors.green : Colors.orange,
        ),
      );

      // 少し待ってから全員回答チェックを実行
      await Future.delayed(const Duration(seconds: 2));
      await _handleAllResponsesCompleted(requestId);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('回答の送信に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      // 処理完了後に処理中状態を解除
      setState(() {
        _processingRequestIds.remove(requestId);
      });
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      await _groupService.sendMessage(
        groupId: widget.group.id,
        message: message,
        type: MessageType.text,
      );
      
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      _showErrorDialog('メッセージの送信に失敗しました: $e');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

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

      setState(() {
        _isSending = true;
      });

      String imageUrl;
      
      if (kIsWeb) {
        // Web版: XFileをUint8Listでアップロード
        final bytes = await image.readAsBytes();
        imageUrl = await _uploadImageBytes(bytes, 'group-message-images');
      } else {
        // モバイル版: Fileでアップロード（HEIC変換含む）
        final originalFile = File(image.path);
        final convertedFile = await _convertHeicToJpeg(originalFile);
        final finalFile = convertedFile ?? originalFile;
        imageUrl = await _uploadImageFile(finalFile, 'group-message-images');
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          // Web版ではカメラボタンを非表示
          if (!kIsWeb)
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('カメラで撮影'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('ギャラリーから選択'),
          ),
        ],
      ),
    );
  }

  // Web版用: Uint8Listで画像アップロード
  Future<String> _uploadImageBytes(Uint8List bytes, String folder) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      // Web版での認証状態確認を強化
      String? token;
      try {
        token = await user.getIdToken(true);
        if (token == null || token.isEmpty) {
          throw Exception('Web版: 認証トークンが無効です。再ログインしてください。');
        }
      } catch (e) {
        throw Exception('Web版: 認証状態が無効です。再ログインしてください。');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('$folder')
          .child(widget.group.id)
          .child(fileName);

      // Web版では明示的に認証トークンを設定
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'userId': user.uid,
          'groupId': widget.group.id,
          'uploadedAt': DateTime.now().toIso8601String(),
          'authToken': token, // 認証トークンをメタデータに含める
        },
      );
      
      final uploadTask = storageRef.putData(bytes, metadata);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      rethrow;
    }
  }

  // モバイル版用: Fileで画像アップロード
  Future<String> _uploadImageFile(File file, String folder) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ユーザーが認証されていません');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${user.uid}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('$folder')
          .child(widget.group.id)
          .child(fileName);

      final uploadTask = storageRef.putFile(file);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
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
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('ログインが必要です');
      final messageData = {
        'type': 'image',
        'imageUrl': imageUrl,
        'senderId': user.uid,
        'senderName': user.displayName ?? 'ユーザー',
        'senderImageUrl': user.photoURL,
        'timestamp': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .collection('messages')
          .add(messageData);
    } catch (e) {
      rethrow;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMemberList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'メンバー (${widget.group.members.length})',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showUserSearchDialog();
                    },
                    icon: const Icon(Icons.person_add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<Group>(
                  stream: FirebaseFirestore.instance.collection('groups').doc(widget.group.id).snapshots()
                      .map((snapshot) => Group.fromMap(snapshot.data()!, snapshot.id)),
                  builder: (context, snapshot) {
                    // 初期化中は前回のデータを保持して点滅を防ぐ
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    
                    final currentGroup = snapshot.data ?? widget.group;
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: currentGroup.members.length,
                      itemBuilder: (context, index) {
                        final memberId = currentGroup.members[index];
                        return _buildMemberTile(memberId, currentGroup);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberTile(String memberId, Group group) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getUserData(memberId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: CircleAvatar(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            title: Text('読み込み中...'),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text('ユーザー ($memberId)'),
            subtitle: Text('読み込みに失敗しました: ${snapshot.error ?? 'Unknown error'}'),
            trailing: const Icon(Icons.warning, color: Colors.orange),
          );
        }

        final userData = snapshot.data!;
        final isAdmin = group.admins.contains(memberId);
        final isCurrentUser = memberId == _groupService.currentUserId;

        return ListTile(
          leading: GestureDetector(
            onTap: () {
              // プロフィール画面に遷移
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileViewPage(userId: memberId),
                ),
              );
            },
            child: CircleAvatar(
              radius: 24,
              backgroundImage: userData['image_url'] != null && userData['image_url'].toString().isNotEmpty
                  ? NetworkImage(userData['image_url'])
                  : null,
              backgroundColor: Colors.grey[300],
              child: userData['image_url'] == null || userData['image_url'].toString().isEmpty
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
          ),
          title: GestureDetector(
            onTap: () {
              // プロフィール画面に遷移
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileViewPage(userId: memberId),
                ),
              );
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    userData['name'] ?? 'ユーザー名不明',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (isAdmin)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '管理者',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          subtitle: userData['bio'] != null && userData['bio'].toString().isNotEmpty
              ? Text(
                  userData['bio'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                )
              : null,
          trailing: isCurrentUser 
              ? null 
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // いいねボタン
                    Builder(
                      builder: (context) {
                        // いいね状態をチェック（複数のIDフィールドを確認）
                        final userIds = [
                          userData['id']?.toString(),
                          userData['uid']?.toString(), 
                          userData['firebase_uid']?.toString(),
                          userData['user_id']?.toString(),
                        ].where((id) => id != null && id.isNotEmpty).toSet();
                        
                        // デバッグ: メンバーIDとのマッチング状況を出力
                        
                        final bool isLiked = _likesLoaded && userIds.any((userId) {
                          final matched = _likedUsers.contains(userId);
                          if (matched) {
                          }
                          return matched;
                        });
                        
                        final String? targetUserId = userIds.isNotEmpty ? userIds.first : null;
                        
                        
                        return GestureDetector(
                          onTap: targetUserId != null 
                              ? () => _sendLikeToMember(targetUserId, userData['name'] ?? 'ユーザー')
                              : null,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isLiked ? Colors.pink : Colors.grey[200],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? Colors.white : Colors.grey[600],
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // 3点メニュー（管理者のみ表示）
                    if (group.admins.contains(_groupService.currentUserId))
                      PopupMenuButton<String>(
                        onSelected: (value) => _handleMemberAction(value, memberId),
                        itemBuilder: (context) => [
                          if (!isAdmin)
                            const PopupMenuItem(
                              value: 'promote',
                              child: Text('管理者にする'),
                            ),
                          if (isAdmin && 
                              memberId != _groupService.currentUserId && // 自分自身は降格できない
                              group.admins.length > 1) // 管理者が1人しかいない場合は降格不可
                            const PopupMenuItem(
                              value: 'demote',
                              child: Text('管理者を解除'),
                            ),
                          if (memberId != _groupService.currentUserId) // 自分自身は削除できない
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('削除'),
                            ),
                        ],
                      ),
                  ],
                ),
        );
      },
    );
  }

  void _showUserSearchDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupMemberSearchPage(group: widget.group),
      ),
    );
  }

  void _showJoinRequestsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupJoinRequestsPage(group: widget.group),
      ),
    );
  }

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      
      // まずFirestoreで直接検索
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('ユーザー情報の取得がタイムアウトしました');
            },
          );
      
      if (doc.exists) {
      final data = doc.data();
      return data;
      }
      
      // Firestoreで見つからない場合、Firebase UIDとしてCloudFunctionでDB検索
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
        final result = await callable.call({
          'firebaseUid': userId,
        }).timeout(const Duration(seconds: 10));
        
        if (result.data != null && result.data['exists'] == true) {
          final userData = result.data['user'];
          return Map<String, dynamic>.from(userData);
        }
      } catch (cloudFunctionError) {
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  void _handleMemberAction(String action, String memberId) async {
    try {
      switch (action) {
        case 'promote':
          await _groupService.promoteToAdmin(widget.group.id, memberId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('管理者権限を付与しました')),
          );
          setState(() {}); // UIを更新
          break;
        case 'demote':
          await _groupService.demoteFromAdmin(widget.group.id, memberId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('管理者権限を削除しました')),
          );
          setState(() {}); // UIを更新
          break;
        case 'remove':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('確認'),
              content: const Text('このメンバーをグループから削除しますか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('削除'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await _groupService.removeMemberFromGroup(widget.group.id, memberId);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('メンバーを削除しました')),
            );
            setState(() {}); // UIを更新
          }
          break;
      }
    } catch (e) {
      String errorMessage = '操作に失敗しました';
      
      if (e.toString().contains('身分証明書認証が必要です')) {
        errorMessage = '管理者権限の付与には身分証明書認証が必要です。\n対象ユーザーが身分証明書認証を完了してから再度お試しください。';
      } else if (e.toString().contains('管理者は最低1人必要です')) {
        errorMessage = '管理者は最低1人必要です。\n他のメンバーを管理者に指定してから実行してください。';
      } else if (e.toString().contains('認証されていません')) {
        errorMessage = 'ログインが必要です';
      } else if (e.toString().contains('権限がありません')) {
        errorMessage = '管理者権限がありません';
      } else if (e.toString().contains('グループが見つかりません')) {
        errorMessage = 'グループが見つかりません';
      } else if (e.toString().contains('指定されたユーザーはグループのメンバーではありません')) {
        errorMessage = '指定されたユーザーはグループのメンバーではありません';
      } else if (e.toString().contains('最後のメンバーはグループから退出できません')) {
        errorMessage = '最後のメンバーはグループから退出できません。\nグループを削除してください。';
      } else {
        errorMessage = 'エラーが発生しました: ${e.toString().replaceAll('Exception: ', '')}';
      }
      
      _showErrorDialog(errorMessage);
    }
  }

  // メンバーにいいねを送る
  Future<void> _sendLikeToMember(String memberId, String memberName) async {
    try {
      await _groupService.sendLikeToUser(memberId);
      
      // いいね状態を更新
      if (mounted) {
        setState(() {
          _likedUsers.add(memberId);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$memberName さんにいいねを送りました！'),
            backgroundColor: Colors.pink,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'いいねの送信に失敗しました';
      if (e.toString().contains('既にいいね済み')) {
        errorMessage = '既にいいねを送信済みです';
      } else if (e.toString().contains('自分自身')) {
        errorMessage = '自分自身にはいいねを送れません';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: widget.group.imageUrl != null && _imagesInitialized
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: WebImageHelper.buildImage(
                        widget.group.imageUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey,
                          ),
                          child: const Icon(Icons.group, size: 40, color: Colors.white),
                        ),
                        errorWidget: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey,
                          ),
                          child: const Icon(Icons.group, size: 40, color: Colors.white),
                        ),
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey,
                      ),
                      child: const Icon(Icons.group, size: 40, color: Colors.white),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.group.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.group.members.length}人のメンバー',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (widget.group.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                widget.group.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
            ],
            // レストラン募集の場合はレストラン情報を表示
            if (widget.group.groupType == 'restaurant_meetup' && widget.group.restaurantInfo != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  children: [
                    // レストラン情報
                    Row(
                      children: [
                        Icon(Icons.restaurant, color: Colors.orange[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'レストラン',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.group.restaurantInfo!['name'] ?? 'レストラン',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.group.restaurantInfo!['category'] != null)
                                Text(
                                  widget.group.restaurantInfo!['category'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _showGroupLocationOnMap();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.map,
                              color: Colors.orange[700],
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 開催日時
                    if (widget.group.eventDateTime != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.orange[600], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '開催日時',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatEventDateTime(widget.group.eventDateTime!),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    // 参加人数
                    if (widget.group.minMembers != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.group, color: Colors.orange[600], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '募集人数',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.group.minMembers}〜${widget.group.maxMembers}人（現在 ${widget.group.members.length}人）',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (widget.group.prefecture != null || widget.group.nearestStation != null) ...[
              // 通常のグループの場合は従来通り
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '活動エリア',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (widget.group.prefecture != null) widget.group.prefecture!,
                              if (widget.group.nearestStation != null) '${widget.group.nearestStation!}駅周辺',
                            ].join(' • '),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _showGroupLocationOnMap();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.map,
                          color: Colors.blue[700],
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.people,
                  label: 'メンバー',
                  onTap: () {
                    Navigator.pop(context);
                    _showMemberList();
                  },
                ),
                if (widget.group.admins.contains(_groupService.currentUserId))
                  _buildActionButton(
                    icon: Icons.how_to_reg,
                    label: '参加申請',
                    onTap: () {
                      Navigator.pop(context);
                      _showJoinRequestsPage();
                    },
                  ),
                _buildActionButton(
                  icon: Icons.location_on,
                  label: '位置情報',
                  onTap: () {
                    Navigator.pop(context);
                    _showGroupLocationOnMap();
                  },
                ),
                _buildActionButton(
                  icon: Icons.settings,
                  label: '設定',
                  onTap: () {
                    Navigator.pop(context);
                    // グループ設定画面へ遷移（実装予定）
                  },
                ),
                _buildActionButton(
                  icon: Icons.exit_to_app,
                  label: '退出',
                  onTap: () {
                    Navigator.pop(context);
                    _showLeaveGroupDialog();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[200],
            child: Icon(icon, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループを退出'),
        content: Text('「${widget.group.name}」から退出しますか？\n\n退出後はメッセージの閲覧や送信ができなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _leaveGroup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _leaveGroup() async {
    try {
      await _groupService.leaveGroup(widget.group.id);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('グループから退出しました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '退出に失敗しました';
        
        if (e.toString().contains('管理者が1人のみの場合')) {
          errorMessage = '管理者が1人のみの場合、退出する前に他のメンバーを管理者に指定してください';
        } else if (e.toString().contains('グループに参加していません')) {
          errorMessage = 'グループに参加していません';
        } else if (e.toString().contains('グループが存在しません')) {
          errorMessage = 'グループが見つかりません';
        } else if (e.toString().contains('認証されていません')) {
          errorMessage = 'ログインが必要です';
        } else {
          errorMessage = 'エラーが発生しました: ${e.toString().replaceAll('Exception: ', '')}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // グループの位置情報を地図で表示
  void _showGroupLocationOnMap() async {
    // レストラン募集の場合はレストランの位置情報を使用
    if (widget.group.groupType == 'restaurant_meetup' && widget.group.restaurantInfo != null) {
      final restaurantInfo = widget.group.restaurantInfo!;
      final latitude = restaurantInfo['latitude'];
      final longitude = restaurantInfo['longitude'];
      final restaurantName = restaurantInfo['name'];
      
      if (latitude != null && longitude != null) {
        try {
          // 緯度経度を使ってGoogle Mapsで開く
          final String googleMapsUrl = 'https://www.google.com/maps?q=$latitude,$longitude';
          
          // レストラン位置情報ダイアログを表示
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.restaurant, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  const Text('レストラン'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurantName ?? 'レストラン',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (restaurantInfo['category'] != null) ...[
                    Text(
                      'カテゴリ: ${restaurantInfo['category']}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (restaurantInfo['prefecture'] != null) ...[
                    Text(
                      '所在地: ${restaurantInfo['prefecture']}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (restaurantInfo['nearestStation'] != null) ...[
                    Text(
                      '最寄駅: ${restaurantInfo['nearestStation']}駅',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Google Mapsでレストランの正確な位置を確認できます',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      final Uri url = Uri.parse(googleMapsUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('地図アプリを開けませんでした'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('エラーが発生しました: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('地図で開く'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
          return;
        } catch (e) {
        }
      }
    }

    // 通常のグループの場合は従来通り駅で検索
    if (widget.group.prefecture == null && widget.group.nearestStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('位置情報が設定されていません'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 検索クエリを作成
    String query = '';
    if (widget.group.nearestStation != null) {
      query = '${widget.group.nearestStation!}駅';
      if (widget.group.prefecture != null) {
        query += ' ${widget.group.prefecture!}';
      }
    } else if (widget.group.prefecture != null) {
      query = widget.group.prefecture!;
    }

    try {
      // Google Mapsで開く
      final String googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
      
      // 位置情報ダイアログを表示
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue[600]),
              const SizedBox(width: 8),
              const Text('活動エリア'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.group.prefecture != null) ...[
                Text(
                  '都道府県: ${widget.group.prefecture!}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ],
              if (widget.group.nearestStation != null) ...[
                Text(
                  '最寄り駅: ${widget.group.nearestStation!}駅',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Google Mapsで詳細な位置を確認できます',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final Uri url = Uri.parse(googleMapsUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('地図アプリを開けませんでした'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('エラーが発生しました: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.map),
              label: const Text('地図で開く'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('位置情報の取得に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteGroup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('グループを削除'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${widget.group.name}」を完全に削除しますか？'),
            const SizedBox(height: 16),
            const Text(
              '⚠️ この操作は取り消せません',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• 全てのメッセージが削除されます\n'
              '• 全てのメンバーがアクセスできなくなります\n'
              '• グループ画像も削除されます',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
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
                  onPressed: () {
                    Navigator.pop(context);
                    _performDeleteGroup();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('削除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _performDeleteGroup() async {
    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('グループを削除中...'),
                ],
              ),
            ),
          ),
        ),
      );

      await _groupService.deleteGroup(widget.group.id);
      
      if (mounted) {
        // ローディングダイアログを閉じる
        Navigator.pop(context);
        
        // グループ一覧画面に戻る
        Navigator.of(context).popUntil((route) => route.isFirst);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('グループを削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ローディングダイアログを閉じる
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 画面をタップしたときにキーボードを閉じる
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title:             GestureDetector(
              onTap: _showGroupInfo,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: widget.group.imageUrl != null && _imagesInitialized
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: WebImageHelper.buildImage(
                              widget.group.imageUrl!,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              placeholder: Container(
                                width: 32,
                                height: 32,
                                color: Colors.grey[200],
                                child: const Icon(Icons.group, size: 16, color: Colors.grey),
                              ),
                              errorWidget: Container(
                                width: 32,
                                height: 32,
                                color: Colors.grey[200],
                                child: const Icon(Icons.group, size: 16, color: Colors.grey),
                              ),
                            ),
                          )
                        : Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey,
                            ),
                            child: const Icon(Icons.group, size: 16, color: Colors.white),
                          ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.group.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.group.members.length}人',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: Colors.pink[400],
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'info':
                    _showGroupInfo();
                    break;
                  case 'search':
                    _showUserSearchDialog();
                    break;
                  case 'requests':
                    _showJoinRequestsPage();
                    break;
                  case 'leave':
                    _showLeaveGroupDialog();
                    break;
                  case 'delete':
                    _deleteGroup();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 8),
                      Text('グループ情報'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Icons.person_add),
                      SizedBox(width: 8),
                      Text('メンバーを招待'),
                    ],
                  ),
                ),
                if (widget.group.admins.contains(_groupService.currentUserId))
                  const PopupMenuItem(
                    value: 'requests',
                    child: Row(
                      children: [
                        Icon(Icons.how_to_reg, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('参加申請管理'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app),
                      SizedBox(width: 8),
                      Text('グループを退出'),
                    ],
                  ),
                ),
                if (widget.group.admins.contains(_groupService.currentUserId))
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever, color: Colors.red),
                        SizedBox(width: 8),
                        Text('グループを削除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // メッセージリスト
            Expanded(
              child: StreamBuilder<List<GroupMessage>>(
                stream: _groupService.getGroupMessages(widget.group.id),
                builder: (context, snapshot) {
                  // 初期化中は前回のデータを保持して点滅を防ぐ
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.pink),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('エラー: ${snapshot.error}'),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'まだメッセージがありません\n最初のメッセージを送信してみましょう！',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMyMessage = message.senderId == _groupService.currentUserId;
                      
                      return _buildMessageBubble(message, isMyMessage);
                    },
                  );
                },
              ),
            ),
            // メッセージ入力欄
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isSending ? null : _sendImage,
                    icon: Icon(
                      Icons.photo,
                      color: _isSending ? Colors.grey : Colors.pink[400],
                    ),
                  ),
                  if (widget.group.admins.contains(_groupService.currentUserId))
                    IconButton(
                      onPressed: _isSending ? null : _showDateRequestDialog,
                      icon: Icon(
                        Icons.restaurant,
                        color: _isSending ? Colors.grey : Colors.pink[400],
                      ),
                      tooltip: 'デートリクエストを送信（管理者のみ）',
                    ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'メッセージを入力...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send,
                            color: Colors.pink[400],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(GroupMessage message, bool isMyMessage) {
    if (message.type == MessageType.system) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        mainAxisAlignment: isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMyMessage) ...[
            GestureDetector(
              onTap: () => _navigateToProfile(message.senderUuid),
              child: _imagesInitialized
                  ? WebImageHelper.buildProfileImage(
                      message.senderImageUrl,
                      size: 32,
                      isCircular: true,
                    )
                  : Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey,
                      ),
                      child: const Icon(Icons.person, size: 16, color: Colors.white),
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMyMessage 
                  ? CrossAxisAlignment.end 
                  : CrossAxisAlignment.start,
              children: [
                if (!isMyMessage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (message.type == MessageType.image && message.imageUrl != null)
                  _buildChatImage(message.imageUrl!)
                else if (message.type == MessageType.group_date_request)
                  _buildGroupDateRequestCard(message, isMyMessage)
                else if (message.type == MessageType.group_date_response)
                  _buildGroupDateResponseCard(message, isMyMessage)
                else if (message.type == MessageType.date_decision)
                  _buildDateDecisionCard(message)
                else if (message.type == MessageType.restaurant_voting)
                  _buildRestaurantVotingCard(message, isMyMessage)
                else if (message.type == MessageType.restaurant_voting_response)
                  _buildRestaurantVotingResponseCard(message, isMyMessage)
                else if (message.type == MessageType.restaurant_decision)
                  _buildRestaurantDecisionCard(message)
                else if (message.message.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMyMessage 
                          ? Colors.blue[100] 
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      message.message,
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 自分のメッセージにはプロフィール画像を表示しない
        ],
      ),
    );
  }

  /// チャット画像表示用のヘルパーメソッド
  Widget _buildChatImage(String imageUrl) {
    return GestureDetector(
      onTap: () => _showImageDialog(imageUrl),
      child: Container(
        width: 200,
        height: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
                      child: WebImageHelper.buildImage(
              imageUrl,
              width: 200,
              height: 150,
              fit: BoxFit.cover,
              placeholder: Container(
                width: 200,
                height: 150,
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: Container(
                width: 200,
                height: 200,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, size: 32, color: Colors.grey),
              ),
            ),
        ),
      ),
    );
  }

  /// グループデートリクエストカード表示
  Widget _buildGroupDateRequestCard(GroupMessage message, bool isMyMessage) {
    final dateRequestData = message.dateRequestData;
    if (dateRequestData == null) return Container();

    final currentUserId = _groupService.currentUserId ?? '';
    final restaurantName = dateRequestData['restaurantName'] ?? '未設定のレストラン';
    final restaurantImageUrl = dateRequestData['restaurantImageUrl'];
    final restaurantCategory = dateRequestData['restaurantCategory'] ?? '';
    final restaurantPrefecture = dateRequestData['restaurantPrefecture'] ?? '';
    final restaurantNearestStation = dateRequestData['restaurantNearestStation'] ?? '';
    final restaurantLowPrice = dateRequestData['restaurantLowPrice'];
    final restaurantHighPrice = dateRequestData['restaurantHighPrice'];
    final restaurantPriceRange = dateRequestData['restaurantPriceRange'] ?? '';
    final proposedDates = List<String>.from(dateRequestData['proposedDates'] ?? []);
    final requestMessage = dateRequestData['message'] ?? '';
    final requesterName = dateRequestData['requesterName'] ?? message.senderName;
    final requestId = message.relatedDateRequestId ?? dateRequestData['requestId'] ?? '';
    

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isMyMessage ? Colors.blue[50] : Colors.pink[50],
        border: Border.all(color: isMyMessage ? Colors.blue[200]! : Colors.pink[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMyMessage ? Colors.blue[100] : Colors.pink[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.restaurant, color: isMyMessage ? Colors.blue[700] : Colors.pink[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'グループデートのお誘い',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMyMessage ? Colors.blue[700] : Colors.pink[700],
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
                if (requestMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      requestMessage,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
                
                // 承認・拒否ボタン（送信者判定はUUIDベースで行う）
                FutureBuilder<String?>(
                  future: _getCurrentUserUuid(),
                  builder: (context, snapshot) {
                    final currentUserUuid = snapshot.data;
                    final isRequestSender = message.senderUuid == currentUserUuid;
                    
                    
                    return Column(
                      children: [
                        const SizedBox(height: 16),
                        StreamBuilder<List<GroupMessage>>(
                          stream: _groupService.getGroupMessages(widget.group.id),
                          builder: (context, snapshot) {
                            bool hasAlreadyResponded = false;
                            bool isDateDecided = false;
                            
                            if (snapshot.hasData) {
                              // 現在のユーザーが既に回答済みかチェック
                              final responses = snapshot.data!.where((msg) => 
                                msg.type == MessageType.group_date_response &&
                                msg.senderUuid == currentUserUuid &&
                                msg.dateRequestData?['originalRequestId'] == requestId
                              ).toList();
                              
                              hasAlreadyResponded = responses.isNotEmpty;
                              
                              // 日程決定済みかチェック
                              final decisionMessages = snapshot.data!.where((msg) => 
                                msg.type == MessageType.date_decision &&
                                msg.dateRequestData?['originalRequestId'] == requestId
                              ).toList();
                              
                              isDateDecided = decisionMessages.isNotEmpty;
                            }
                            
                            if (isDateDecided) {
                              // 日程が決定済みの場合：何も表示しない（予約案内は日程決定カードに表示）
                              return const SizedBox.shrink();
                            } else if (isRequestSender) {
                              // リクエスト送信者で日程未決定の場合：何も表示しない
                              return const SizedBox.shrink();
                            } else if (hasAlreadyResponded) {
                              // 既に回答済みで日程未決定の場合：何も表示しない
                              return const SizedBox.shrink();
                            }
                            
                            // 処理中の場合は何も表示しない（二重押し防止）
                            if (_processingRequestIds.contains(requestId)) {
                              return Container(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '処理中...',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            
                            return Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _respondToDateRequest(requestId, 'accept', proposedDates),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.pink,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('承認する'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _respondToDateRequest(requestId, 'reject', proposedDates),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.grey),
                                    ),
                                    child: const Text('辞退する'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                
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

  /// 予約案内セクション（デートリクエストカード用）
  Widget _buildReservationGuidanceSection(String requestId, Map<String, dynamic> dateRequestData) {
    final restaurantName = dateRequestData['restaurantName'] ?? '未設定のレストラン';
    final restaurantId = dateRequestData['restaurantId']?.toString();
    
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.keyboard_arrow_down,
                size: 24,
                color: Colors.blue,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _showReservationConfirmDialog(requestId, restaurantName, restaurantId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
        ),
      ],
    );
  }

  /// 日程決定カード表示
  Widget _buildDateDecisionCard(GroupMessage message) {
    final dateDecisionData = message.dateRequestData;
    if (dateDecisionData == null) return Container();

    final status = dateDecisionData['status'] ?? '';
    final decidedDate = dateDecisionData['decidedDate'];
    final restaurantName = dateDecisionData['restaurantName'] ?? '';
    final approvedCount = dateDecisionData['approvedCount'] ?? 0;
    final tiedDates = dateDecisionData['tiedDates'] as List<dynamic>?;

    IconData iconData;
    Color cardColor;
    Color iconColor;

    switch (status) {
      case 'decided':
        iconData = Icons.celebration;
        cardColor = Colors.green[50]!;
        iconColor = Colors.green;
        break;
      case 'all_rejected':
        iconData = Icons.cancel;
        cardColor = Colors.red[50]!;
        iconColor = Colors.red;
        break;
      case 'tie':
        iconData = Icons.schedule;
        cardColor = Colors.orange[50]!;
        iconColor = Colors.orange;
        break;
      default:
        iconData = Icons.info;
        cardColor = Colors.grey[50]!;
        iconColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: iconColor.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(
                iconData,
                size: 32,
                color: iconColor,
              ),
              const SizedBox(height: 8),
              Text(
                _getDecisionTitle(status),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message.message,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              if (status == 'decided' && decidedDate != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '📅 ${_formatDecidedDate(decidedDate)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🏪 $restaurantName',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (status == 'tie' && tiedDates != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '引き分けの候補日程:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...tiedDates.map((date) => Text(
                        '• ${_formatDecidedDate(date)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                                // 再投票ボタン（元の送信者のみ表示）
                FutureBuilder<bool>(
                  future: _isOriginalRequestSender(dateDecisionData),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              final originalRequestId = dateDecisionData['originalRequestId'] ?? '';
                              
                              // 元のリクエストメッセージからrestaurantId等を取得
                              final messages = await _groupService.getGroupMessages(widget.group.id).first;
                              Map<String, dynamic>? originalRequestData;
                              
                              for (final msg in messages) {
                                if (msg.type == MessageType.group_date_request && 
                                    msg.dateRequestData?['requestId'] == originalRequestId) {
                                  originalRequestData = {
                                    'requestId': originalRequestId,
                                    'restaurantId': msg.dateRequestData?['restaurantId'],
                                    'restaurantName': msg.dateRequestData?['restaurantName'],
                                    'proposedDates': msg.dateRequestData?['proposedDates'] ?? [],
                                    'additionalRestaurantIds': msg.dateRequestData?['additionalRestaurantIds'] ?? [],
                                    'restaurantLowPrice': msg.dateRequestData?['restaurantLowPrice'],
                                    'restaurantHighPrice': msg.dateRequestData?['restaurantHighPrice'],
                                    'restaurantNearestStation': msg.dateRequestData?['restaurantNearestStation'],
                                  };
                                  break;
                                }
                              }
                              
                              if (originalRequestData == null) {
                                throw Exception('元のリクエストデータが見つかりません');
                              }
                              
                              await _startTieBreakVoting(originalRequestId, tiedDates.cast<String>(), originalRequestData);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('再投票の開始に失敗しました: $e'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.how_to_vote, size: 16),
                              SizedBox(width: 6),
                              Text(
                                '再投票を開始',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink(); // 送信者でない場合は何も表示しない
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getDecisionTitle(String status) {
    switch (status) {
      case 'decided':
        return '🎉 日程決定！';
      case 'all_rejected':
        return '😔 開催見送り';
      case 'tie':
        return '🤔 再調整が必要';
      default:
        return 'お知らせ';
    }
  }

  String _formatDecidedDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('M/d(E) HH:mm', 'ja').format(date);
    } catch (e) {
      return dateString;
    }
  }

  /// 元のリクエスト送信者かどうかを判定
  Future<bool> _isOriginalRequestSender(Map<String, dynamic> dateDecisionData) async {
    final originalRequestId = dateDecisionData['originalRequestId'] ?? '';
    if (originalRequestId.isEmpty) return false;

    // 現在のユーザーUUIDを取得
    final currentUserUuid = await _getCurrentUserUuid();
    if (currentUserUuid == null) return false;

    // StreamBuilderから最新のメッセージリストを使用する必要があるため、
    // 現在のStreaqmからデータを取得
    return _groupService.getGroupMessages(widget.group.id).first.then((messages) {
      for (final message in messages) {
        if (message.type == MessageType.group_date_request && 
            message.dateRequestData?['requestId'] == originalRequestId) {
          final originalSenderUuid = message.senderUuid;
          final isOriginalSender = originalSenderUuid == currentUserUuid;
          return isOriginalSender;
        }
      }
      return false;
    });
  }

  /// グループデートレスポンスカード表示
  Widget _buildGroupDateResponseCard(GroupMessage message, bool isMyMessage) {
    final dateRequestData = message.dateRequestData;
    if (dateRequestData == null) return Container();

    final response = dateRequestData['response'] ?? '';
    final selectedDate = dateRequestData['selectedDate'];
    final isAccepted = response == 'accept';

    // メッセージの送信者情報を使用（実際のユーザー画像・名前）
    final responderName = message.senderName;
    final responderImageUrl = message.senderImageUrl;


    return Container(
      width: 250,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAccepted ? Colors.green[50] : Colors.red[50],
        border: Border.all(
          color: isAccepted ? Colors.green[200]! : Colors.red[200]!,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ユーザー情報とレスポンス
          Row(
            children: [
              // ユーザー画像
              GestureDetector(
                onTap: () => _navigateToProfile(message.senderUuid),
                child: _imagesInitialized
                    ? WebImageHelper.buildProfileImage(
                        responderImageUrl,
                        size: 32,
                        isCircular: true,
                      )
                    : Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                        child: const Icon(Icons.person, size: 16, color: Colors.white),
                      ),
              ),
              const SizedBox(width: 8),
              // レスポンス内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isAccepted ? Icons.check_circle : Icons.cancel,
                          color: isAccepted ? Colors.green[700] : Colors.red[700],
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isAccepted ? 'デートリクエストを承認' : 'デートリクエストを辞退',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isAccepted ? Colors.green[700] : Colors.red[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'by $responderName',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          if (selectedDate != null && isAccepted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Builder(
                builder: (context) {
                  try {
                    // 複数選択の場合はカンマ区切りで分割
                    final selectedDates = selectedDate.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toList();
                    
                    if (selectedDates.isEmpty) return Container();
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '選択日時${selectedDates.length > 1 ? ' (${selectedDates.length}個)' : ''}:',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...selectedDates.map((dateStr) {
                          try {
                            final date = DateTime.parse(dateStr);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.schedule, size: 12, color: Colors.green[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('MM/dd(E) HH:mm', 'ja').format(date),
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            return Container();
                          }
                        }).toList(),
                      ],
                    );
                  } catch (e) {
                    return Container();
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }



  /// 全メンバーの回答状況をチェックして日程決定
  Future<Map<String, dynamic>?> _checkAllMembersResponseAndDecideDate(String requestId) async {
    try {
      // グループメンバー数を取得
      final totalMembers = widget.group.members.length;
      
      // このグループの全メッセージを取得してリクエストと回答を確認
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .collection('messages')
          .get();

      // リクエスト送信者とリクエスト情報を特定
      String? requestSenderId;
      Map<String, dynamic>? originalRequestData;
      final requestMessages = messagesSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['type'] == 'group_date_request' && 
               data['dateRequestData']?['requestId'] == requestId;
      }).toList();

      if (requestMessages.isNotEmpty) {
        final requestData = requestMessages.first.data();
        requestSenderId = requestData['senderId'];
        originalRequestData = requestData['dateRequestData'];
      }

      if (requestSenderId == null || originalRequestData == null) {
        return null;
      }

      // このリクエストに対する回答を集計
      final responseMessages = messagesSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['type'] == 'group_date_response' && 
               data['relatedDateRequestId'] == requestId;
      }).toList();

      // 回答者のリスト（送信者は除く）
      Set<String> respondedMembers = {};
      Map<String, String> memberResponses = {}; // memberId -> 'accept'/'reject'
      Map<String, String> memberSelectedDates = {}; // memberId -> selectedDate
      Set<String> approvedMembers = {requestSenderId}; // 送信者は自動承認
      
      for (final responseDoc in responseMessages) {
        final data = responseDoc.data();
        final response = data['dateRequestData']?['response'];
        final senderId = data['senderId'];
        final selectedDate = data['dateRequestData']?['selectedDate'];
        
        if (senderId != null && senderId != requestSenderId) {
          respondedMembers.add(senderId);
          memberResponses[senderId] = response ?? 'reject';
          
          if (response == 'accept') {
            approvedMembers.add(senderId);
            if (selectedDate != null) {
              memberSelectedDates[senderId] = selectedDate;
            }
          }
        }
      }

      // 送信者以外の全員が回答したかチェック
      final requiredResponses = totalMembers - 1; // 送信者を除く
      final actualResponses = respondedMembers.length;
      
      
      if (actualResponses < requiredResponses) {
        return null;
      }

      // 承認者が送信者のみの場合（全員拒否）
      if (approvedMembers.length == 1) {
        return {
          'status': 'all_rejected',
          'approvedCount': approvedMembers.length,
        };
      }

      // 承認者の日程を集計（送信者は元の候補日程から選択と仮定）
      final dateVotes = <String, int>{};
      
      // リクエスト送信者の分も含めて集計するため、元の候補日程を取得
      final proposedDates = List<String>.from(originalRequestData['proposedDates'] ?? []);
      
      // 他のメンバーの選択日程をカウント（複数選択対応）
      for (final selectedDateString in memberSelectedDates.values) {
        // 複数選択の場合はカンマ区切りで分割
        final selectedDates = selectedDateString.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toList();
        
        for (final selectedDate in selectedDates) {
          dateVotes[selectedDate] = (dateVotes[selectedDate] ?? 0) + 1;
        }
      }

      // 送信者の分として、最も人気の日程に1票追加（または候補日程の最初に1票）
      if (dateVotes.isNotEmpty) {
        // 既に票が入っている日程の中で最多のものに送信者の票を追加
        final maxVotes = dateVotes.values.reduce((a, b) => a > b ? a : b);
        final topDate = dateVotes.entries.firstWhere((entry) => entry.value == maxVotes).key;
        dateVotes[topDate] = dateVotes[topDate]! + 1;
      } else if (proposedDates.isNotEmpty) {
        // 誰も選択していない場合、最初の候補日程に送信者の票を入れる
        dateVotes[proposedDates.first] = 1;
      }


      if (dateVotes.isEmpty) {
        return null;
      }

      // 最多得票の日程を取得
      final maxVotes = dateVotes.values.reduce((a, b) => a > b ? a : b);
      final topDates = dateVotes.entries
          .where((entry) => entry.value == maxVotes)
          .map((entry) => entry.key)
          .toList();

      if (topDates.length > 1) {
        return {
          'status': 'tie',
          'tiedDates': topDates,
          'votes': maxVotes,
          'originalRequestData': originalRequestData,
          'approvedCount': approvedMembers.length,
        };
      }

      // 日程決定
      final decidedDate = topDates.first;
      
      return {
        'status': 'decided',
        'decidedDate': decidedDate,
        'votes': maxVotes,
        'originalRequestData': originalRequestData,
        'totalMembers': totalMembers,
        'approvedCount': approvedMembers.length,
      };
      
    } catch (e) {
      return null;
    }
  }

  /// 全員回答後の結果処理
  Future<void> _handleAllResponsesCompleted(String requestId) async {
    final result = await _checkAllMembersResponseAndDecideDate(requestId);
    
    if (result == null) return;

    switch (result['status']) {
      case 'all_rejected':
        // Cloud Functionsが既にシステムメッセージを送信するため、何もしない
        break;
        
      case 'tie':
        // Cloud Functionsが既にシステムメッセージを送信するため、何もしない
        break;
        
      case 'decided':
        // Cloud Functionsが既にシステムメッセージを送信するため、何もしない
        break;
    }
  }

  /// 予約案内カード生成
  Future<void> _generateReservationCard(
    String decidedDate, 
    Map<String, dynamic> originalRequestData,
    int approvedCount
  ) async {
    await _requestReservation(
      originalRequestData['requestId'] ?? '',
      originalRequestData['restaurantName'] ?? 'レストラン',
      originalRequestData['restaurantId']?.toString(),
    );
  }

  /// 予約案内カード表示
  Widget _buildReservationCard(Map<String, dynamic> dateRequestData, String requestId) {
    final restaurantName = dateRequestData['restaurantName'] ?? '未設定のレストラン';
    final originalRequestId = dateRequestData['originalRequestId'] ?? requestId;
    
    return Container(
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
                _showReservationConfirmDialog(originalRequestId, restaurantName, restaurantId);
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
    );
  }

  /// 予約確認ダイアログ表示
  Future<void> _showReservationConfirmDialog(String requestId, String restaurantName, String? restaurantId) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.restaurant_menu, color: Colors.blue),
            const SizedBox(width: 8),
            const Expanded(child: Text('予約案内')),
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

  /// 予約リクエスト処理
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
            const Icon(Icons.restaurant, color: Colors.pink),
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
                  backgroundColor: Colors.pink.withOpacity(0.1),
                  child: Icon(
                    option['icon'] == 'phone' ? Icons.phone : Icons.web,
                    color: Colors.pink,
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

  /// 予約完了報告ダイアログ
  Future<void> _showReservationCompletedDialog(String requestId, String restaurantName) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('予約完了'),
          ],
        ),
        content: Text('$restaurantNameの予約が完了しました！\nグループメンバーに報告されました。'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// 画像拡大表示ダイアログ
  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
                          child: InteractiveViewer(
              child: WebImageHelper.buildImage(
                imageUrl,
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.8,
                fit: BoxFit.contain,
                placeholder: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.8,
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
                errorWidget: Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, size: 64, color: Colors.grey),
                ),
              ),
            ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🎨 最もシンプルな画像表示（完全無フィルター）
  Widget _buildProperImage(String imageUrl, {
    required BoxFit fit,
    double? width,
    double? height,
    Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
    Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  }) {
    
    // ファイル名からHEIC変換済みかどうかを判定
    final bool isConvertedHeic = imageUrl.contains('converted_heic_') && imageUrl.endsWith('.jpg');
    
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorBuilder?.call(context, error, stackTrace) ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image, size: 28, color: Colors.grey),
            );
      },
    );
  }

  /// 現在のユーザーのUUIDを取得
  Future<String?> _getCurrentUserUuid() async {
    try {
      final currentUserId = _groupService.currentUserId;
      if (currentUserId == null) return null;

      // Cloud FunctionでFirebase UIDからUUIDを取得
      final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
      final result = await callable.call({'firebaseUid': currentUserId});
      
      if (result.data != null && result.data['exists'] == true) {
        return result.data['user']['id'];
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }



  /// 再投票開始
  Future<void> _startTieBreakVoting(
    String originalRequestId, 
    List<String> tiedDates, 
    Map<String, dynamic> originalRequestData
  ) async {
    try {
      // 引き分け候補日程で新しいデートリクエストを送信するかダイアログで確認
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.how_to_vote, color: Colors.orange),
              SizedBox(width: 8),
              Text('再投票を開始'),
            ],
          ),
          content: Text(
            '引き分けとなった候補日程で再度投票を行いますか？\n\n候補日程:\n${tiedDates.map((date) => '• ${_formatDecidedDate(date)}').join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('再投票開始'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        // 再投票用のデートリクエストを直接送信
        await _sendTieBreakDateRequest(originalRequestData, tiedDates);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('再投票の開始に失敗しました'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// 引き分け時の再投票リクエスト送信
  Future<void> _sendTieBreakDateRequest(
    Map<String, dynamic> originalRequestData,
    List<String> tiedDates
  ) async {
    try {
      // デバッグ: パラメータの内容を詳しく確認
      
      final restaurantId = originalRequestData['restaurantId']?.toString();
      if (restaurantId == null || restaurantId.isEmpty) {
        throw Exception('restaurantIdが見つかりません');
      }

      // 元のリクエストから必要な情報を取得
      final additionalRestaurantIds = originalRequestData['additionalRestaurantIds'];
      final restaurantLowPrice = originalRequestData['restaurantLowPrice'];
      final restaurantHighPrice = originalRequestData['restaurantHighPrice'];
      final restaurantNearestStation = originalRequestData['restaurantNearestStation'];
      

      final callable = FirebaseFunctions.instance.httpsCallable('sendGroupDateRequest');
      final result = await callable.call({
        'groupId': widget.group.id,
        'restaurantId': restaurantId,
        'additionalRestaurantIds': additionalRestaurantIds ?? [],
        'proposedDates': tiedDates,
        'message': '前回は引き分けとなったため、再度投票をお願いします！🗳️',
        'isRetry': true,
        'restaurantLowPrice': restaurantLowPrice,
        'restaurantHighPrice': restaurantHighPrice,
        'restaurantNearestStation': restaurantNearestStation,
      });
      
      if (result.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('再投票リクエストを送信しました'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(result.data['error'] ?? '再投票リクエストの送信に失敗しました');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('再投票リクエストの送信に失敗しました: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      rethrow;
    }
  }

  /// 店舗投票カード表示
  Widget _buildRestaurantVotingCard(GroupMessage message, bool isMyMessage) {
    final votingData = message.restaurantVotingData;
    if (votingData == null) return Container();

    final currentUserId = _groupService.currentUserId ?? '';
    final restaurants = List<Map<String, dynamic>>.from(votingData['restaurants'] ?? []);
    final decidedDate = votingData['decidedDate'] ?? '';
    final votingId = votingData['restaurantVotingId'] ?? '';
    final originalRequestId = votingData['originalRequestId'] ?? '';

    // 投票済みかチェック & リクエスト送信者かチェック & 辞退者かチェック
    return FutureBuilder<Map<String, bool>>(
      future: Future.wait([
        _isAlreadyVotedForRestaurant(votingId),
        _isOriginalRequestSender({'originalRequestId': originalRequestId}),
        _isRejectUser(originalRequestId),
      ]).then((results) => {
        'isAlreadyVoted': results[0],
        'isRequestSender': results[1],
        'isRejectUser': results[2],
      }),
      builder: (context, snapshot) {
        final isAlreadyVoted = snapshot.data?['isAlreadyVoted'] ?? false;
        final isRequestSender = snapshot.data?['isRequestSender'] ?? false;
        final isRejectUser = snapshot.data?['isRejectUser'] ?? false;
        
        // ローカル状態での投票完了もチェック
        final isLocallyCompleted = _completedVotingIds.contains(votingId);
        
        // 辞退者、リクエスト送信者、投票済み、ローカル完了済みの場合は投票UI不要
        final shouldShowVotingUI = !isAlreadyVoted && !isRequestSender && !isRejectUser && !isLocallyCompleted;
        
        return Container(
          width: 300,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: shouldShowVotingUI ? Colors.green[50] : Colors.grey[100],
            border: Border.all(color: shouldShowVotingUI ? Colors.green[200]! : Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: shouldShowVotingUI ? Colors.green[100] : Colors.grey[200],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      shouldShowVotingUI ? Icons.store : Icons.check_circle, 
                      color: shouldShowVotingUI ? Colors.green[700] : Colors.grey[600], 
                      size: 20
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child:                 Text(
                  isRejectUser
                      ? '店舗投票（参加辞退済み）'
                      : isRequestSender 
                          ? '店舗投票（自動投票済み）'
                          : (isAlreadyVoted || isLocallyCompleted)
                              ? '店舗投票（回答済み）' 
                              : '店舗投票（複数選択可）',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: shouldShowVotingUI ? Colors.green[700] : Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 日程表示
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '📅 ${_formatDecidedDate(decidedDate)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              if (isRejectUser) ...[
                // 辞退者の場合
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'あなたはこの企画を辞退されているため、\n店舗投票には参加できません。',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              ] else if (isRequestSender) ...[
                // リクエスト送信者の場合
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'あなたは全ての店舗に自動的に投票されています。\n他のメンバーの回答をお待ちください。',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              ] else if (isAlreadyVoted || isLocallyCompleted) ...[
                // 投票済みの場合（Firestore確認済み + ローカル完了済み）
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '投票が完了しています。\n他のメンバーの回答をお待ちください。',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              ] else ...[
                // 投票可能な場合
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _processingVotingIds.contains(votingId)
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
                              '処理中...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () => _showRestaurantSelectionDialog(votingId, restaurants),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('店舗を選択する'),
                      ),
                ),
              ],
              
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// 店舗投票回答カード表示
  Widget _buildRestaurantVotingResponseCard(GroupMessage message, bool isMyMessage) {
    final responseData = message.restaurantVotingResponseData;
    if (responseData == null) return Container();

    final selectedRestaurantIds = responseData['selectedRestaurantIds'] ?? '';
    // 文字列を分割して空でないIDの数をカウント
    final selectedCount = selectedRestaurantIds.toString().split(',')
        .where((id) => id.trim().isNotEmpty)
        .length;
    
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
              '${message.senderName}が${selectedCount}店舗を選択しました',
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

  /// 店舗決定カード表示
  Widget _buildRestaurantDecisionCard(GroupMessage message) {
    final decisionData = message.restaurantVotingData;
    if (decisionData == null) return Container();

    final status = decisionData['status'] ?? '';
    final decidedRestaurantName = decisionData['decidedRestaurantName'] ?? '';
    final decidedRestaurantId = decisionData['decidedRestaurantId'] ?? '';
    final decidedDate = decisionData['decidedDate'] ?? '';
    final voteCount = decisionData['voteCount'] ?? 0;
    final originalVotingData = decisionData['originalVotingData'] as Map<String, dynamic>?;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status == 'decided' ? Colors.green[50] : Colors.orange[50],
        border: Border.all(
          color: status == 'decided' ? Colors.green[200]! : Colors.orange[200]!
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
            // 予約案内ボタン（日程と店舗が決定した後に表示）
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final originalRequestId = originalVotingData?['originalRequestId'] ?? '';
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
              message.message,
              style: TextStyle(
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            // 引き分けの場合の再投票ボタン
            if (decisionData['tiedRestaurants'] != null) ...[
              const SizedBox(height: 12),
              FutureBuilder<bool>(
                future: _isOriginalRequestSender({'originalRequestId': originalVotingData?['originalRequestId'] ?? ''}),
                builder: (context, snapshot) {
                  final isRequestSender = snapshot.data ?? false;
                  
                  if (!isRequestSender) {
                    return Container(); // リクエスト送信者でない場合は非表示
                  }
                  
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _startRestaurantTieBreakVoting(
                        decisionData['originalVotingId'] ?? '',
                        decisionData['tiedRestaurants'] as List<dynamic>? ?? [],
                        originalVotingData,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.replay, size: 16),
                          SizedBox(width: 6),
                          Text(
                            '再投票を開始',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// 投票済みかチェック
  Future<bool> _isAlreadyVotedForRestaurant(String votingId) async {
    try {
      final currentUserId = _groupService.currentUserId;
      if (currentUserId == null) return false;

      final responseQuery = FirebaseFirestore.instance
          .collection("groups")
          .doc(widget.group.id)
          .collection("messages")
          .where("type", isEqualTo: "restaurant_voting_response")
          .where("relatedDateRequestId", isEqualTo: votingId)
          .where("senderId", isEqualTo: currentUserId);

      final responseSnapshot = await responseQuery.get();
      return responseSnapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 店舗選択ダイアログ表示
  void _showRestaurantSelectionDialog(String votingId, List<Map<String, dynamic>> restaurants) {
    // 既に処理中の場合は何もしない（二重押し防止）
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
    
    Set<String> selectedRestaurantIds = {};
    bool isProcessing = false; // ダイアログ内での処理中状態
    
    showDialog(
      context: context,
      barrierDismissible: true, // 通常は閉じられるが、処理中は関数で制御
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => WillPopScope(
          onWillPop: () async => !isProcessing, // 処理中は戻るボタンを無効化
          child: AlertDialog(
          title: const Text('希望店舗を選択してください\n（複数選択可能）'),
          content: restaurants.isEmpty 
            ? const Text('選択可能な店舗がありません')
            : SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '選択済み: ${selectedRestaurantIds.length}店舗',
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
                          final isSelected = selectedRestaurantIds.contains(restaurantId);
                          
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  selectedRestaurantIds.add(restaurantId);
                                } else {
                                  selectedRestaurantIds.remove(restaurantId);
                                }
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
                                    ),
                                  )
                                : const Icon(Icons.restaurant),
                            controlAffinity: ListTileControlAffinity.trailing,
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
              onPressed: (selectedRestaurantIds.isNotEmpty && !isProcessing)
                  ? () async {
                      // ダイアログ内での処理中状態を設定
                      setState(() {
                        isProcessing = true;
                      });
                      
                      // メイン画面の処理中状態に設定
                      this.setState(() {
                        _processingVotingIds.add(votingId);
                      });
                      
                      Navigator.pop(context);
                      _respondToRestaurantVoting(votingId, selectedRestaurantIds.toList());
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
        ), // AlertDialog
      ), // WillPopScope 
    ), // StatefulBuilder
  ); // showDialog
  }

  /// 店舗投票回答
  Future<void> _respondToRestaurantVoting(String votingId, List<String> selectedRestaurantIds) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('respondToRestaurantVoting');
      final result = await callable.call({
        'restaurantVotingId': votingId,
        'selectedRestaurantIds': selectedRestaurantIds,
        'responseMessage': '店舗を選択しました！',
      });
      
      if (result.data['success'] == true) {
        // 投票成功時にローカル状態に追加
        setState(() {
          _completedVotingIds.add(votingId);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('店舗投票に回答しました'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(result.data['message'] ?? '投票に失敗しました');
      }
    } catch (e) {
      
      String errorMessage = '投票に失敗しました';
      if (e.toString().contains('already-exists')) {
        errorMessage = '既に投票済みです';
        // 既に投票済みの場合もローカル状態に追加
        setState(() {
          _completedVotingIds.add(votingId);
        });
      } else if (e.toString().contains('店舗投票に回答済みです')) {
        errorMessage = '既に投票済みです';
        // 既に投票済みの場合もローカル状態に追加
        setState(() {
          _completedVotingIds.add(votingId);
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: errorMessage.contains('投票済み') ? Colors.orange : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      // 処理完了後に処理中状態を解除
      setState(() {
        _processingVotingIds.remove(votingId);
      });
    }
  }

  /// 店舗再投票を開始
  Future<void> _startRestaurantTieBreakVoting(
    String originalVotingId,
    List<dynamic> tiedRestaurants,
    Map<String, dynamic>? originalData,
  ) async {
    try {
      // デバッグ: パラメータの内容を確認
      
      // 引き分け店舗のIDを抽出
      final tiedRestaurantIds = <String>[];
      for (int i = 0; i < tiedRestaurants.length; i++) {
        try {
          final restaurant = tiedRestaurants[i];
          
          String? restaurantId;
          if (restaurant is Map<String, dynamic>) {
            restaurantId = restaurant['id']?.toString();
          } else if (restaurant is String) {
            restaurantId = restaurant;
          } else {
            restaurantId = restaurant?.toString();
          }
          
          
          if (restaurantId != null && restaurantId.isNotEmpty) {
            tiedRestaurantIds.add(restaurantId);
          }
        } catch (e) {
        }
      }
      
      
      if (tiedRestaurantIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('引き分け店舗の取得に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable('startRestaurantTieBreakVoting');
      
      final result = await callable.call({
        'originalVotingId': originalVotingId,
        'tiedRestaurantIds': tiedRestaurantIds,
        'originalData': originalData ?? {},
      });

      if (result.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('店舗の再投票を開始しました！'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.data['message'] ?? '再投票の開始に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('再投票の開始に失敗しました: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 辞退者かどうかをチェック
  Future<bool> _isRejectUser(String originalRequestId) async {
    try {
      final currentUserId = _groupService.currentUserId;
      if (currentUserId == null) return false;

      // 現在のユーザーがこのリクエストに対して辞退回答をしているかチェック
      final responseQuery = FirebaseFirestore.instance
          .collection("groups")
          .doc(widget.group.id)
          .collection("messages")
          .where("type", isEqualTo: "group_date_response")
          .where("relatedDateRequestId", isEqualTo: originalRequestId)
          .where("senderId", isEqualTo: currentUserId);

      final responseSnapshot = await responseQuery.get();

      for (final doc in responseSnapshot.docs) {
        final responseData = doc.data()['dateRequestData'];
        if (responseData?['response'] == 'reject') {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }


}


