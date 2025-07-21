import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/group_model.dart';

class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // 現在のユーザーID取得
  String? get currentUserId => _auth.currentUser?.uid;
  
  // 身分証明認証状態を確認
  Future<bool> _isIdentityVerified() async {
    try {
      if (currentUserId == null) return false;
      
      final callable = _functions.httpsCallable('getUserByFirebaseUid');
      final result = await callable.call({'firebaseUid': currentUserId});
      
      if (result.data != null && result.data['exists'] == true) {
        return result.data['user']['id_verified'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // グループ検索
  Stream<List<Group>> searchGroups({
    String? keyword,
    String? category,
    String? prefecture,
    String? nearestStation,
    int? minMembers,
    int? maxMembers,
    bool? isPrivate,
    List<String>? tags,
  }) {
    Query query = _firestore.collection('groups');

    // プライベートでないグループのみを検索対象とする
    query = query.where('isPrivate', isEqualTo: false);

    // カテゴリフィルター
    if (category != null && category.isNotEmpty) {
      query = query.where('category', isEqualTo: category);
    }

    // 都道府県フィルター
    if (prefecture != null && prefecture.isNotEmpty) {
      query = query.where('prefecture', isEqualTo: prefecture);
    }

    // 最寄駅フィルター
    if (nearestStation != null && nearestStation.isNotEmpty) {
      query = query.where('nearestStation', isEqualTo: nearestStation);
    }

    return query.snapshots().map((snapshot) {
      List<Group> groups = snapshot.docs
          .map((doc) => Group.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      // キーワード検索（クライアント側フィルタリング）
      if (keyword != null && keyword.isNotEmpty) {
        final lowerKeyword = keyword.toLowerCase();
        groups = groups.where((group) {
          return group.name.toLowerCase().contains(lowerKeyword) ||
                 group.description.toLowerCase().contains(lowerKeyword);
        }).toList();
      }

      // 人数フィルター（クライアント側フィルタリング）
      if (minMembers != null) {
        groups = groups.where((group) => group.members.length >= minMembers).toList();
      }
      if (maxMembers != null) {
        groups = groups.where((group) => group.members.length <= maxMembers).toList();
      }

      // ハッシュタグフィルター（クライアント側フィルタリング）
      if (tags != null && tags.isNotEmpty) {
        groups = groups.where((group) {
          if (group.tags == null || group.tags!.isEmpty) return false;
          return tags.any((tag) => group.tags!.contains(tag));
        }).toList();
      }

      // 最新順でソート
      groups.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.updatedAt;
        final bTime = b.lastMessageAt ?? b.updatedAt;
        return bTime.compareTo(aTime);
      });

      return groups;
    });
  }

  // グループ作成
  Future<String> createGroup({
    required String name,
    required String description,
    String? imageUrl,
    bool isPrivate = false,
    int maxMembers = 100,
    List<String> initialMembers = const [],
    String? category,
    String? prefecture,
    String? nearestStation,
    List<String>? tags,
  }) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');
    
    // 身分証明認証状態をチェック
    final isVerified = await _isIdentityVerified();
    if (!isVerified) {
      throw Exception('グループの作成・管理には身分証明書認証が必要です。\n設定画面から身分証明書認証を完了してください。');
    }

    final now = DateTime.now();
    final members = [currentUserId!, ...initialMembers];
    final admins = [currentUserId!];

    final groupData = {
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'createdBy': currentUserId,
      'members': members,
      'admins': admins,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'lastMessage': null,
      'lastMessageAt': null,
      'lastMessageBy': null,
      'isPrivate': isPrivate,
      'maxMembers': maxMembers,
      'category': category,
      'prefecture': prefecture,
      'nearestStation': nearestStation,
      'tags': tags,
    };

    final docRef = await _firestore.collection('groups').add(groupData);
    
    // システムメッセージを追加
    await _sendSystemMessage(
      groupId: docRef.id,
      message: 'グループが作成されました',
    );

    return docRef.id;
  }

  // レストラン募集用グループ作成
  Future<String> createRestaurantGroup({
    required String name,
    required Map<String, dynamic> restaurantInfo,
    required DateTime eventDateTime,
    DateTime? eventEndDateTime,
    required int minMembers,
    required int maxMembers,
    String? description,
  }) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      // ローカル時間をUTCに変換してからISO文字列として送信
      
      // ローカル時間をUTCに変換
      final utcEventDateTime = eventDateTime.toUtc();
      final utcEventEndDateTime = eventEndDateTime?.toUtc();
      
      
      final callable = _functions.httpsCallable('createGroup');
      final result = await callable.call({
        'name': name,
        'description': description ?? '',
        'groupType': 'restaurant_meetup',
        'restaurantInfo': restaurantInfo,
        'eventDateTime': utcEventDateTime.toIso8601String(),
        'eventEndDateTime': utcEventEndDateTime?.toIso8601String(),
        'minMembers': minMembers,
        'maxMembers': maxMembers,
        'isPublic': true,
        // レストランの位置情報をグループの位置情報として設定
        'prefecture': restaurantInfo['prefecture'],
        'nearestStation': restaurantInfo['nearestStation'],
        'category': restaurantInfo['category'], // レストランのカテゴリも設定
      });

      if (result.data['success'] == true) {
        return result.data['groupId'];
      } else {
        throw Exception(result.data['error'] ?? 'グループ作成に失敗しました');
      }
    } catch (e) {
      throw Exception('レストラン募集の作成に失敗しました: $e');
    }
  }

  // レストラン募集グループを取得（マップ表示用）
  Stream<List<Group>> getRestaurantMeetupGroups() {
    
    try {
      // 一時的にorderByを削除してインデックス問題を回避
      final query = _firestore
          .collection('groups')
          .where('isPrivate', isEqualTo: false);
      
      
      return query.snapshots().map((snapshot) {
        
        final groups = <Group>[];
        int processedCount = 0;
        int validCount = 0;
        
        for (final doc in snapshot.docs) {
          try {
            processedCount++;
            final data = doc.data() as Map<String, dynamic>;
            
            // デバッグ情報を詳細に出力
            
            final group = Group.fromMap(data, doc.id);
            
            // レストラン募集グループの条件を詳細にチェック
            final hasGroupType = group.groupType == 'restaurant_meetup';
            final hasRestaurantInfo = group.restaurantInfo != null;
            final isPrivate = group.isPrivate;
            
            
            // レストラン募集グループの条件：
            // 1. groupType が 'restaurant_meetup' である
            // 2. または restaurantInfo が存在する（旧データとの互換性）
            // 3. かつ isPrivate が false である
            final isRestaurantMeetup = (hasGroupType || hasRestaurantInfo) && !isPrivate;
            
            if (isRestaurantMeetup && hasRestaurantInfo) {
              groups.add(group);
              validCount++;
              
              // レストラン情報の詳細を出力
              final restaurantInfo = group.restaurantInfo!;
            } else {
              if (!isRestaurantMeetup) {
              } else if (!hasRestaurantInfo) {
              }
            }
          } catch (e, stackTrace) {
          }
        }
        
        
        // クライアント側でソート
        groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        return groups;
      }).handleError((error) {
        return <Group>[];
      });
    } catch (e) {
      return Stream.value(<Group>[]);
    }
  }

  // グループ情報取得
  Future<Group?> getGroup(String groupId) async {
    final doc = await _firestore.collection('groups').doc(groupId).get();
    if (!doc.exists) return null;
    return Group.fromMap(doc.data()!, doc.id);
  }

  // ユーザーが参加しているグループ一覧取得
  Stream<List<Group>> getUserGroups() {
    if (currentUserId == null) return Stream.value([]);
    
    return _firestore
        .collection('groups')
        .where('members', arrayContains: currentUserId)
        // orderByを一時的に削除（Firestoreインデックス作成待ち）
        .snapshots()
        .map((snapshot) {
      final groups = snapshot.docs
          .map((doc) => Group.fromMap(doc.data(), doc.id))
          .toList();
      
      // クライアント側でソート
      groups.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.updatedAt;
        final bTime = b.lastMessageAt ?? b.updatedAt;
        return bTime.compareTo(aTime);
      });
      
      return groups;
    });
  }

  // ユーザーが参加しているグループ + 招待されたグループの一覧取得
  Stream<List<GroupWithStatus>> getUserGroupsWithInvitations() {
    if (currentUserId == null) return Stream.value([]);
    
    // 参加済みグループのStream
    final memberGroupsStream = _firestore
        .collection('groups')
        .where('members', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupWithStatus(
                  group: Group.fromMap(doc.data(), doc.id),
                  status: GroupStatus.member,
                  invitationId: null,
                ))
            .toList());

    // 現在のユーザーのUUIDを取得してから招待を検索
    return memberGroupsStream.asyncMap((memberGroups) async {
      List<GroupWithStatus> invitedGroups = [];
      
      try {
        // 現在のユーザー（招待を受ける側）の情報を取得
        
        // 招待受信者の情報を取得（Cloud Function + Firestore フォールバック）
        String? actualUserId;
        String? userName;
        
        try {
          // まずCloud FunctionでDB検索を試行
          final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
          final result = await callable.call({'firebaseUid': currentUserId});
          
          if (result.data != null && result.data['exists'] == true) {
            actualUserId = result.data['user']['id'];
            userName = result.data['user']['name'] ?? 'ユーザー';
          } else {
            throw Exception('Cloud Functionで招待受信者が見つかりません');
          }
        } catch (e) {
          
          // Cloud Functionが失敗した場合、Firestoreで直接検索
          try {
            final userDoc = await _firestore.collection('users').doc(currentUserId).get();
            if (userDoc.exists) {
              final userData = userDoc.data()!;
              actualUserId = currentUserId; // Firebase UIDをそのまま使用
              userName = userData['name'] ?? 'ユーザー';
            } else {
              throw Exception('Firestoreでも招待受信者が見つかりません');
            }
          } catch (firestoreError) {
            throw Exception('招待受信者の情報が見つかりません');
          }
        }
        
        if (actualUserId != null && userName != null) {
          
          // UUIDで招待を検索
          final invitationSnapshot = await _firestore
              .collection('group_invitations')
              .where('inviteeId', isEqualTo: actualUserId)
              .where('status', isEqualTo: 'pending')
              .get();
          
          
          // 全ての招待データを詳細表示
          for (int i = 0; i < invitationSnapshot.docs.length; i++) {
            final doc = invitationSnapshot.docs[i];
            final data = doc.data();
          }
          
          for (final doc in invitationSnapshot.docs) {
            final data = doc.data();
            final groupId = data['groupId'];
            final invitationId = doc.id;
            
            
            try {
              final groupDoc = await _firestore.collection('groups').doc(groupId).get();
              if (groupDoc.exists) {
                final group = Group.fromMap(groupDoc.data()!, groupDoc.id);
                invitedGroups.add(GroupWithStatus(
                  group: group,
                  status: GroupStatus.invited,
                  invitationId: invitationId,
                ));
              } else {
              }
            } catch (e) {
            }
          }
        } else {
        }
      } catch (e) {
      }
      
      final combined = [...memberGroups, ...invitedGroups];
      
      
      // ソート（招待されたグループを上に、その後は最新メッセージ順）
      combined.sort((a, b) {
        // 招待されたグループを優先
        if (a.status == GroupStatus.invited && b.status != GroupStatus.invited) {
          return -1;
        }
        if (b.status == GroupStatus.invited && a.status != GroupStatus.invited) {
          return 1;
        }
        
        // 同じステータスの場合は最新メッセージ順
        final aTime = a.group.lastMessageAt ?? a.group.updatedAt;
        final bTime = b.group.lastMessageAt ?? b.group.updatedAt;
        return bTime.compareTo(aTime);
      });
      
      return combined;
    });
  }

  // グループに参加申請を送信する
  Future<void> requestToJoinGroup(String groupId, {String? message}) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      final groupRef = _firestore.collection('groups').doc(groupId);
      final groupDoc = await groupRef.get();
      
      if (!groupDoc.exists) {
        throw Exception('グループが見つかりません');
      }

      final groupData = groupDoc.data()!;
      final groupName = groupData['name'] ?? 'グループ';
      final members = List<String>.from(groupData['members'] ?? []);
      
      if (members.contains(currentUserId)) {
        throw Exception('既にグループのメンバーです');
      }

      // 既存の申請をチェック
      final existingRequest = await _firestore
          .collection('group_join_requests')
          .where('groupId', isEqualTo: groupId)
          .where('applicantId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequest.docs.isNotEmpty) {
        throw Exception('既に参加申請を送信済みです');
      }

      // ユーザー情報を取得
      String? userName;
      String? userImageUrl;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
        final result = await callable.call({'firebaseUid': currentUserId});
        
        if (result.data != null && result.data['exists'] == true) {
          userName = result.data['user']['name'] ?? 'ユーザー';
          userImageUrl = result.data['user']['image_url'];
        } else {
          throw Exception('ユーザー情報が見つかりません');
        }
      } catch (e) {
        final searchUsersFunction = _functions.httpsCallable('searchUsers');
        final searchResult = await searchUsersFunction.call({
          'query': '', 
          'limit': 100,
        });
        
        final data = searchResult.data;
        if (data is Map<String, dynamic> && data.containsKey('users')) {
          final usersData = data['users'];
          if (usersData is List) {
            final users = usersData.map((user) {
              if (user is Map<String, dynamic>) {
                return user;
              } else {
                return Map<String, dynamic>.from(user as Map);
              }
            }).toList();
            
            final targetUser = users.firstWhere(
              (user) => user['firebase_uid'] == currentUserId,
              orElse: () => <String, dynamic>{},
            );
            
            if (targetUser.isNotEmpty) {
              userName = targetUser['name'] ?? targetUser['displayName'] ?? 'ユーザー';
              userImageUrl = targetUser['image_url'];
            } else {
              userName = 'ユーザー';
            }
          }
        }
      }

      // 参加申請を作成
      await _firestore.collection('group_join_requests').add({
        'groupId': groupId,
        'groupName': groupName,
        'applicantId': currentUserId,
        'applicantName': userName,
        'applicantImageUrl': userImageUrl,
        'status': 'pending',
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // グループ管理者に通知を送信
      final adminIds = List<String>.from(groupData['admins'] ?? []);
      for (final adminId in adminIds) {
        await _sendJoinRequestNotification(
          adminId: adminId,
          groupName: groupName,
          applicantName: userName ?? 'ユーザー',
        );
      }


    } catch (e) {
      throw Exception('参加申請の送信に失敗しました: $e');
    }
  }

  // 参加申請一覧を取得（グループ管理者用）
  Stream<List<GroupJoinRequest>> getJoinRequestsForGroup(String groupId) {
    try {
      return _firestore
          .collection('group_join_requests')
          .where('groupId', isEqualTo: groupId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
            try {
              final requests = snapshot.docs.map((doc) {
                try {
                  final data = doc.data();
                  return GroupJoinRequest.fromMap(data, doc.id);
                } catch (e) {
                  return null;
                }
              }).where((request) => request != null).cast<GroupJoinRequest>().toList();
              
              return requests;
            } catch (e) {
              return <GroupJoinRequest>[];
            }
          }).handleError((error) {
            return <GroupJoinRequest>[];
          });
    } catch (e) {
      return Stream.value(<GroupJoinRequest>[]);
    }
  }

  // 参加申請を承認
  Future<void> approveJoinRequest(String requestId, String groupId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      // 管理者権限をチェック
      final isAdmin = await isGroupAdmin(groupId);
      if (!isAdmin) {
        throw Exception('グループの管理者権限が必要です');
      }

      // 申請情報を取得
      final requestDoc = await _firestore
          .collection('group_join_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        throw Exception('参加申請が見つかりません');
      }

      final requestData = requestDoc.data()!;
      final applicantId = requestData['applicantId'];
      final applicantName = requestData['applicantName'] ?? 'ユーザー';

      // グループにメンバーとして追加
      await _firestore.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([applicantId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 申請ステータスを承認済みに更新
      await _firestore.collection('group_join_requests').doc(requestId).update({
        'status': 'approved',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // グループにシステムメッセージを送信
      await _sendSystemMessage(
        groupId: groupId,
        message: '$applicantName さんがグループに参加しました',
      );

      // 申請者に承認通知を送信
      await _sendJoinApprovalNotification(
        applicantId: applicantId,
        groupName: requestData['groupName'],
      );


    } catch (e) {
      throw Exception('参加申請の承認に失敗しました: $e');
    }
  }

  // 参加申請を拒否
  Future<void> rejectJoinRequest(String requestId, String groupId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      // 管理者権限をチェック
      final isAdmin = await isGroupAdmin(groupId);
      if (!isAdmin) {
        throw Exception('グループの管理者権限が必要です');
      }

      // 申請情報を取得
      final requestDoc = await _firestore
          .collection('group_join_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        throw Exception('参加申請が見つかりません');
      }

      final requestData = requestDoc.data()!;
      final applicantId = requestData['applicantId'];

      // 申請ステータスを拒否済みに更新
      await _firestore.collection('group_join_requests').doc(requestId).update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // 申請者に拒否通知を送信
      await _sendJoinRejectionNotification(
        applicantId: applicantId,
        groupName: requestData['groupName'],
      );


    } catch (e) {
      throw Exception('参加申請の拒否に失敗しました: $e');
    }
  }

  // ユーザーが送信した参加申請一覧を取得
  Stream<List<GroupJoinRequest>> getUserJoinRequests() {
    if (currentUserId == null) return Stream.value([]);

    return _firestore
        .collection('group_join_requests')
        .where('applicantId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupJoinRequest.fromMap(doc.data(), doc.id))
            .toList());
  }

  // 参加申請通知を送信（管理者向け）
  Future<void> _sendJoinRequestNotification({
    required String adminId,
    required String groupName,
    required String applicantName,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(adminId).get();
      final userData = userDoc.data();
      final fcmToken = userData?['fcm_token'];

      if (fcmToken != null) {
        final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
        await callable.call({
          'token': fcmToken,
          'title': 'グループ参加申請',
          'body': '$applicantName さんから「$groupName」への参加申請が届きました',
          'data': {
            'type': 'join_request',
            'group_name': groupName,
            'applicant_name': applicantName,
          },
        });
      }
    } catch (e) {
    }
  }

  // 参加承認通知を送信
  Future<void> _sendJoinApprovalNotification({
    required String applicantId,
    required String groupName,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(applicantId).get();
      final userData = userDoc.data();
      final fcmToken = userData?['fcm_token'];

      if (fcmToken != null) {
        final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
        await callable.call({
          'token': fcmToken,
          'title': '参加申請が承認されました',
          'body': '「$groupName」グループへの参加申請が承認されました！',
          'data': {
            'type': 'join_approved',
            'group_name': groupName,
          },
        });
      }
    } catch (e) {
    }
  }

  // 参加拒否通知を送信
  Future<void> _sendJoinRejectionNotification({
    required String applicantId,
    required String groupName,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(applicantId).get();
      final userData = userDoc.data();
      final fcmToken = userData?['fcm_token'];

      if (fcmToken != null) {
        final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
        await callable.call({
          'token': fcmToken,
          'title': '参加申請について',
          'body': '「$groupName」グループへの参加申請が見送られました',
          'data': {
            'type': 'join_rejected',
            'group_name': groupName,
          },
        });
      }
    } catch (e) {
    }
  }

  // 招待承認時の直接参加機能（招待システム用）
  Future<void> _directJoinGroup(String groupId, String? userName) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      final groupRef = _firestore.collection('groups').doc(groupId);
      final groupDoc = await groupRef.get();
      
      if (!groupDoc.exists) {
        throw Exception('グループが見つかりません');
      }

      final groupData = groupDoc.data()!;
      final members = List<String>.from(groupData['members'] ?? []);
      
      if (members.contains(currentUserId)) {
        throw Exception('既にグループのメンバーです');
      }

      // メンバーリストに追加
      members.add(currentUserId!);
      
      await groupRef.update({
        'members': members,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // システムメッセージを送信
      await _sendSystemMessage(
        groupId: groupId,
        message: '${userName ?? 'ユーザー'} さんがグループに参加しました',
      );

    } catch (e) {
      throw Exception('グループへの参加に失敗しました: $e');
    }
  }

  // グループに参加する
  Future<void> joinGroup(String groupId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      final groupRef = _firestore.collection('groups').doc(groupId);
      final groupDoc = await groupRef.get();
      
      if (!groupDoc.exists) {
        throw Exception('グループが見つかりません');
      }

      final groupData = groupDoc.data()!;
      final members = List<String>.from(groupData['members'] ?? []);
      
      if (members.contains(currentUserId)) {
        throw Exception('既にグループのメンバーです');
      }

      // ユーザー情報を取得（Cloud Function使用）
      String? userName;
      try {
        // Cloud Functionでユーザー情報を取得
        final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
        final result = await callable.call({'firebaseUid': currentUserId});
        
        if (result.data != null && result.data['exists'] == true) {
                      userName = result.data['user']['name'] ?? 'ユーザー';
        } else {
          // Cloud Functionで見つからない場合、searchUsersで検索
          final searchUsersFunction = _functions.httpsCallable('searchUsers');
          final searchResult = await searchUsersFunction.call({
            'query': '', // 空のクエリで全ユーザーを取得
            'limit': 100,
          });
          
          final data = searchResult.data;
          if (data is Map<String, dynamic> && data.containsKey('users')) {
            final usersData = data['users'];
            if (usersData is List) {
              final users = usersData.map((user) {
                if (user is Map<String, dynamic>) {
                  return user;
                } else {
                  return Map<String, dynamic>.from(user as Map);
                }
              }).toList();
              
              // Firebase UIDで検索
              final targetUser = users.firstWhere(
                (user) => user['firebase_uid'] == currentUserId,
                orElse: () => <String, dynamic>{},
              );
              
              if (targetUser.isNotEmpty) {
                userName = targetUser['name'] ?? targetUser['displayName'] ?? 'ユーザー';
              } else {
                userName = 'ユーザー';
              }
            }
          }
        }
      } catch (e) {
        userName = 'ユーザー';
      }

      // メンバーリストに追加
      members.add(currentUserId!);
      
      await groupRef.update({
        'members': members,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // システムメッセージを送信
      await _sendSystemMessage(
        groupId: groupId,
        message: '$userName さんがグループに参加しました',
      );

    } catch (e) {
      throw Exception('グループへの参加に失敗しました: $e');
    }
  }

  // グループ招待を送信
  Future<void> inviteUserToGroup(String groupId, String userId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      // グループ情報を取得
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        throw Exception('グループが見つかりません');
      }

      final groupData = groupDoc.data()!;
      final groupName = groupData['name'] ?? 'グループ';

      // 招待者の情報を取得
      
      // 招待者の情報を取得（Cloud Function + Firestore フォールバック）
      String? actualUserId;
      String? inviterName;
      
      try {
        // まずCloud FunctionでDB検索を試行
        final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
        final result = await callable.call({'firebaseUid': currentUserId});
        
        if (result.data != null && result.data['exists'] == true) {
          actualUserId = result.data['user']['id'];
                      inviterName = result.data['user']['name'] ?? 'ユーザー';
        } else {
          throw Exception('Cloud Functionで招待者が見つかりません');
        }
      } catch (e) {
        
        // Cloud Functionが失敗した場合、Firestoreで直接検索
        try {
          final userDoc = await _firestore.collection('users').doc(currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            actualUserId = currentUserId; // Firebase UIDをそのまま使用
            inviterName = userData['name'] ?? 'ユーザー';
          } else {
            throw Exception('Firestoreでも招待者が見つかりません');
          }
        } catch (firestoreError) {
          throw Exception('招待者の情報が見つかりません');
        }
      }
      
      if (actualUserId != null && inviterName != null) {
        // 招待対象ユーザーの情報を取得
        
        // Cloud Function searchUsersから直接ユーザー情報を取得
        String? inviteeName;
        try {
          
          final searchUsersFunction = _functions.httpsCallable('searchUsers');
          final searchResult = await searchUsersFunction.call({
            'query': '', // 空のクエリで全ユーザーを取得
            'limit': 100,
          });
          
          // 型キャストを安全に実行
          final data = searchResult.data;
          
          if (data is Map<String, dynamic> && data.containsKey('users')) {
            final usersData = data['users'];
            if (usersData is List) {
              final users = usersData.map((user) {
                if (user is Map<String, dynamic>) {
                  return user;
                } else {
                  // Map<Object?, Object?>をMap<String, dynamic>に変換
                  return Map<String, dynamic>.from(user as Map);
                }
              }).toList();
              
              
              // 指定されたUUIDでユーザーを検索
              final targetUser = users.firstWhere(
                (user) => user['id'] == userId,
                orElse: () => <String, dynamic>{},
              );
              
              if (targetUser.isNotEmpty) {
                inviteeName = targetUser['name'] ?? 'ユーザー';
              } else {
                throw Exception('招待対象のユーザーが見つかりません');
              }
            } else {
              throw Exception('usersデータの形式が不正です');
            }
          } else {
            throw Exception('searchUsers結果の形式が不正です');
          }
        } catch (e) {
          throw Exception('招待対象のユーザーが見つかりません');
        }
        
        if (inviteeName == null) {
          throw Exception('招待対象のユーザーが見つかりません');
        }
        
        // 既存の招待をチェック
        final existingInvitation = await _firestore
            .collection('group_invitations')
            .where('groupId', isEqualTo: groupId)
            .where('inviteeId', isEqualTo: userId)
            .where('status', isEqualTo: 'pending')
            .get();

        if (existingInvitation.docs.isNotEmpty) {
          throw Exception('既に招待を送信済みです');
        }

        // 招待を作成
        await _firestore.collection('group_invitations').add({
          'groupId': groupId,
          'groupName': groupName,
          'inviterId': actualUserId,
          'inviterName': inviterName,
          'inviteeId': userId,
          'inviteeName': inviteeName,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });


        // グループにシステムメッセージを送信
        await _sendSystemMessage(
          groupId: groupId,
          message: '$inviteeName さんをグループに招待しました',
        );

        // 招待対象ユーザーに通知を送信
        await _sendInvitationNotification(
          inviteeId: userId,
          groupName: groupName,
          inviterName: inviterName,
        );

        return;
      }
      
      throw Exception('招待者の情報が見つかりません');
    } catch (e) {
      
      // 具体的なエラーメッセージを設定
      String errorMessage = '招待の送信に失敗しました';
      if (e.toString().contains('既に招待を送信済み')) {
        errorMessage = '既に招待を送信済みです';
      } else if (e.toString().contains('見つかりません')) {
        errorMessage = 'ユーザーまたはグループが見つかりません';
      } else if (e.toString().contains('permission')) {
        errorMessage = '招待の権限がありません';
      }
      
      throw Exception(errorMessage);
    }
  }

  // グループから退出
  Future<void> leaveGroup(String groupId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    final groupRef = _firestore.collection('groups').doc(groupId);
    
    await _firestore.runTransaction((transaction) async {
      final groupDoc = await transaction.get(groupRef);
      if (!groupDoc.exists) throw Exception('グループが存在しません');

      final group = Group.fromMap(groupDoc.data()!, groupDoc.id);
      
      if (!group.members.contains(currentUserId)) {
        throw Exception('グループに参加していません');
      }

      final updatedMembers = group.members.where((id) => id != currentUserId).toList();
      final updatedAdmins = group.admins.where((id) => id != currentUserId).toList();
      
      // 管理者が自分のみの状態で退出することを防ぐ制約
      if (group.admins.contains(currentUserId) && group.admins.length == 1 && updatedMembers.isNotEmpty) {
        throw Exception('管理者が1人のみの場合、退出する前に他のメンバーを管理者に指定してください');
      }
      
      // 最後のメンバーが退出しようとする場合を防ぐ
      if (group.members.length == 1) {
        throw Exception('最後のメンバーはグループから退出できません。グループを削除してください。');
      }
      
      // 管理者が1人もいなくなる場合、新しい管理者を指定
      if (updatedAdmins.isEmpty && updatedMembers.isNotEmpty) {
        updatedAdmins.add(updatedMembers.first);
      }
      
      transaction.update(groupRef, {
        'members': updatedMembers,
        'admins': updatedAdmins,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });

    // 退出通知メッセージを送信
    String? userName;
    try {
      // Cloud Functionでユーザー名を取得
      final callable = _functions.httpsCallable('getUserByFirebaseUid');
      final result = await callable.call({'firebaseUid': currentUserId});
      
      if (result.data != null && result.data['exists'] == true) {
        userName = result.data['user']['name'] ?? 'ユーザー';
      }
    } catch (e) {
      // Cloud Functionが失敗した場合、Firestoreで取得
      final userDoc = await _firestore.collection('users').doc(currentUserId).get();
      userName = userDoc.data()?['name'] ?? 'ユーザー';
    }
    
    try {
      await _sendSystemMessage(
        groupId: groupId,
        message: '$userName さんがグループから退出しました',
      );
    } catch (e) {
      // グループが削除されている場合はエラーを無視
    }
  }

  // HEIC/HEIFをJPEGに変換
  Future<File> _convertHeicToJpeg(File originalFile) async {
    try {

      // ファイル拡張子をチェック
      final fileExtension = originalFile.path.split('.').last.toLowerCase();
      
      // ファイルの実際の内容を確認（マジックナンバーチェック）
      final bytes = await originalFile.readAsBytes();
      
      // バイト配列の最初の16バイトを16進数で表示
      final hexHeader = bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      
      // ASCIIで解釈可能な部分を表示
      final asciiHeader = String.fromCharCodes(bytes.take(16).where((b) => b >= 32 && b <= 126));
      
      final isActuallyHeic = _isHeicFile(bytes);
      
      // HEIC/HEIFファイルかどうかチェック（拡張子または実際の内容）
      if (fileExtension == 'heic' || fileExtension == 'heif' || isActuallyHeic) {
        
        // 画像をデコード
        final decodedImage = img.decodeImage(bytes);
        
        if (decodedImage != null) {
          
          // 色を補正せずに、元の色情報を保持したままJPEGに変換
          final jpegBytes = img.encodeJpg(decodedImage, quality: 95);
          
          final tempDir = await getTemporaryDirectory();
          final convertedFile = File('${tempDir.path}/message_converted_heic_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await convertedFile.writeAsBytes(jpegBytes);
          
          
          return convertedFile;
        } else {
          return originalFile;
        }
      }
      
      // HEIC/HEIFでない場合、または変換に失敗した場合は元のファイルを返す
      
      // JPEG/PNGでも詳細情報を表示
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage != null) {
      }
      
      return originalFile;
    } catch (e, stackTrace) {
      return originalFile;
    }
  }

  // ファイルの実際の内容がHEIC/HEIFかどうかを判定
  bool _isHeicFile(Uint8List bytes) {
    if (bytes.length < 12) {
      return false;
    }
    
    // HEIC/HEIFファイルのマジックナンバーをチェック
    // "ftyp" (66 74 79 70) が4バイト目から始まり、その後に "heic", "heix", "hevx", "heif" などが続く
    if (bytes.length >= 12) {
      final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
      
      if (ftyp == 'ftyp') {
        final brand = String.fromCharCodes(bytes.sublist(8, 12));
        
        // HEIC/HEIF関連のブランドをチェック
        final isHeicHeif = brand == 'heic' || brand == 'heix' || brand == 'hevx' || brand == 'heim' ||
                          brand == 'heif' || brand == 'heis' || brand == 'hevc' || brand == 'hevs' ||
                          brand == 'avif' || brand == 'avis';
        return isHeicHeif;
      } else {
      }
    }
    
    // 追加チェック: HEIFファイルの別パターン
    // 一部のHEIFファイルは異なる位置にftypヘッダーを持つ場合がある
    for (int i = 0; i < bytes.length - 12; i++) {
      if (i + 12 < bytes.length) {
        final possibleFtyp = String.fromCharCodes(bytes.sublist(i, i + 4));
        if (possibleFtyp == 'ftyp') {
          final possibleBrand = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
          
          final isHeicHeif = possibleBrand == 'heic' || possibleBrand == 'heix' || possibleBrand == 'hevx' || 
                            possibleBrand == 'heim' || possibleBrand == 'heif' || possibleBrand == 'heis' ||
                            possibleBrand == 'hevc' || possibleBrand == 'hevs' || possibleBrand == 'avif' || 
                            possibleBrand == 'avis';
          if (isHeicHeif) {
            return true;
          }
        }
      }
    }
    
    return false;
  }

  // メッセージ送信
  Future<void> sendMessage({
    required String groupId,
    required String message,
    MessageType type = MessageType.text,
    File? imageFile,
    String? replyToId,
  }) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    String? imageUrl;
    
    // 画像がある場合はアップロード
    if (imageFile != null) {
      // HEIC/HEIFをJPEGに変換
      final convertedFile = await _convertHeicToJpeg(imageFile);
      imageUrl = await uploadMessageImage(convertedFile, groupId);
    }

    // ユーザー情報取得（Cloud Functionを使用）
    String senderName = 'ユーザー';
    String? senderImageUrl;
    String? senderUuid;
    
    try {
      // 正しいCloud Function（getUserByFirebaseUid）を使用（グループ一覧と同じ方法）
      final callable = _functions.httpsCallable('getUserByFirebaseUid');
      final result = await callable.call({
        'firebaseUid': currentUserId,
      });
      
      
      if (result.data != null && result.data['exists'] == true && result.data['user'] != null) {
        final user = result.data['user'];
        senderUuid = user['id'];
        senderName = user['name'] ?? 'ユーザー';
        senderImageUrl = user['image_url'];
      } else {
        
        // 最終フォールバック：firebase_uidを使用
        senderUuid = currentUserId;
      }
    } catch (e) {
      senderUuid = currentUserId; // エラー時フォールバック：firebase_uidを使用
    }
    

    final now = DateTime.now();
    final messageData = {
      'groupId': groupId,
      'senderId': currentUserId,
      'senderUuid': senderUuid,
      'senderName': senderName,
      'senderImageUrl': senderImageUrl,
      'message': message,
      'type': type.toString().split('.').last,
      'imageUrl': imageUrl,
      'timestamp': Timestamp.fromDate(now),
      'isDeleted': false,
      'replyToId': replyToId,
      'readBy': {currentUserId!: true},
    };

    // メッセージを保存
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add(messageData);

    // グループの最新メッセージ情報を更新
    await _firestore.collection('groups').doc(groupId).update({
      'lastMessage': message,
      'lastMessageAt': Timestamp.fromDate(now),
      'lastMessageBy': currentUserId,
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  // システムメッセージ送信
  Future<void> _sendSystemMessage({
    required String groupId,
    required String message,
  }) async {
    final now = DateTime.now();
    final messageData = {
      'groupId': groupId,
      'senderId': 'system',
      'senderUuid': null,
      'senderName': 'システム',
      'senderImageUrl': null,
      'message': message,
      'type': MessageType.system.toString().split('.').last,
      'imageUrl': null,
      'timestamp': Timestamp.fromDate(now),
      'isDeleted': false,
      'replyToId': null,
      'readBy': <String, bool>{},
    };

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add(messageData);
  }

  // グループメッセージ取得
  Stream<List<GroupMessage>> getGroupMessages(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => GroupMessage.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // メッセージを既読にする
  Future<void> markMessageAsRead(String groupId, String messageId) async {
    if (currentUserId == null) return;

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .update({
      'readBy.$currentUserId': true,
    });
  }

  // 画像アップロード
  Future<String> uploadGroupImage(File imageFile, String groupId) async {
    
    final fileName = 'group_${groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    
    final ref = _storage.ref().child('group-images/$fileName');
    
    try {
      final uploadTask = ref.putFile(imageFile);
      
      // アップロード進捗を監視
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
      });
      
      final snapshot = await uploadTask;
      
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  // メッセージ画像アップロード
  Future<String> uploadMessageImage(File imageFile, String groupId) async {
    
    final fileName = 'message_${groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    
    final ref = _storage.ref().child('group-message-images/$groupId/$fileName');
    
    try {
      final uploadTask = ref.putFile(imageFile);
      
      // アップロード進捗を監視
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
      });
      
      final snapshot = await uploadTask;
      
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  // 招待通知を送信
  Future<void> _sendInvitationNotification({
    required String inviteeId,
    required String groupName,
    required String inviterName,
  }) async {
    try {
      // 招待対象ユーザーのFCMトークンを取得
      final userDoc = await _firestore.collection('users').doc(inviteeId).get();
      final userData = userDoc.data();
      final fcmToken = userData?['fcm_token'];

      if (fcmToken != null) {
        // Cloud Functionsを使って通知を送信
        final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
        await callable.call({
          'token': fcmToken,
          'title': 'グループ招待',
          'body': '$inviterName さんから「$groupName」グループに招待されました',
          'data': {
            'type': 'group_invitation',
            'group_name': groupName,
            'inviter_name': inviterName,
          },
        });
      } else {
      }
    } catch (e) {
      // 通知送信に失敗しても招待自体は成功とする
    }
  }

  // グループ情報更新
  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? imageUrl,
    bool? isPrivate,
    int? maxMembers,
  }) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    final updateData = <String, dynamic>{
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };

    if (name != null) updateData['name'] = name;
    if (description != null) updateData['description'] = description;
    if (imageUrl != null) updateData['imageUrl'] = imageUrl;
    if (isPrivate != null) updateData['isPrivate'] = isPrivate;
    if (maxMembers != null) updateData['maxMembers'] = maxMembers;

    await _firestore.collection('groups').doc(groupId).update(updateData);
  }

  // メンバーをグループに追加
  Future<void> addMemberToGroup(String groupId, String userId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // 追加通知メッセージを送信
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final userName = userDoc.data()?['name'] ?? 'ユーザー';
    
    await _sendSystemMessage(
      groupId: groupId,
      message: '$userName さんがグループに追加されました',
    );
  }

  // メンバーをグループから削除
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    // グループ情報を取得して権限チェック
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) throw Exception('グループが見つかりません');

    final groupData = groupDoc.data()!;
    final members = List<String>.from(groupData['members'] ?? []);
    final admins = List<String>.from(groupData['admins'] ?? []);
    
    // 現在のユーザーが管理者権限を持っているかチェック
    if (!admins.contains(currentUserId)) {
      throw Exception('管理者権限がありません');
    }

    // 削除対象ユーザーがメンバーに含まれているかチェック
    if (!members.contains(userId)) {
      throw Exception('指定されたユーザーはグループのメンバーではありません');
    }

    // 削除対象ユーザーが管理者の場合、管理者が1人しかいない場合は削除を防ぐ
    if (admins.contains(userId) && admins.length <= 1) {
      throw Exception('管理者は最低1人必要です。他のメンバーを管理者に指定してから実行してください。');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([userId]),
      'admins': FieldValue.arrayRemove([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    // 削除通知メッセージを送信
    String? userName;
    try {
      // Cloud Functionでユーザー名を取得
      final callable = _functions.httpsCallable('getUserByFirebaseUid');
      final result = await callable.call({'firebaseUid': userId});
      
      if (result.data != null && result.data['exists'] == true) {
        userName = result.data['user']['name'] ?? 'ユーザー';
      }
    } catch (e) {
      // Cloud Functionが失敗した場合、Firestoreで取得
      final userDoc = await _firestore.collection('users').doc(userId).get();
      userName = userDoc.data()?['name'] ?? 'ユーザー';
    }
    
    await _sendSystemMessage(
      groupId: groupId,
      message: '$userName さんがグループから削除されました',
    );
  }

  // 管理者権限付与
  Future<void> promoteToAdmin(String groupId, String userId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    // 管理者権限を付与される対象ユーザーの身分証明認証状態をチェック
    try {
      final callable = _functions.httpsCallable('getUserByFirebaseUid');
      final result = await callable.call({'firebaseUid': userId});
      
      if (result.data != null && result.data['exists'] == true) {
        final isVerified = result.data['user']['id_verified'] == true;
        if (!isVerified) {
          throw Exception('管理者権限の付与には身分証明書認証が必要です。\n対象ユーザーが身分証明書認証を完了してから再度お試しください。');
        }
      } else {
        throw Exception('対象ユーザーが見つかりません');
      }
    } catch (e) {
      throw Exception('管理者権限の付与に失敗しました: $e');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'admins': FieldValue.arrayUnion([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // 管理者権限削除
  Future<void> demoteFromAdmin(String groupId, String userId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    // グループ情報を取得して管理者数をチェック
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) throw Exception('グループが見つかりません');

    final groupData = groupDoc.data()!;
    final admins = List<String>.from(groupData['admins'] ?? []);
    
    // 管理者が1人しかいない場合は降格を防ぐ
    if (admins.length <= 1) {
      throw Exception('管理者は最低1人必要です。他のメンバーを管理者に指定してから実行してください。');
    }
    
    // 現在のユーザーが管理者権限を持っているかチェック
    if (!admins.contains(currentUserId)) {
      throw Exception('管理者権限がありません');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'admins': FieldValue.arrayRemove([userId]),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // グループ削除（管理者のみ）
  Future<void> deleteGroup(String groupId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      // グループ情報を取得
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        throw Exception('グループが見つかりません');
      }

      final groupData = groupDoc.data()!;
      final admins = List<String>.from(groupData['admins'] ?? []);
      
      // 管理者権限チェック
      if (!admins.contains(currentUserId)) {
        throw Exception('グループを削除する権限がありません');
      }


      // バッチ処理でデータを削除
      final batch = _firestore.batch();

      // 1. グループのメッセージを削除
      final messagesQuery = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .get();

      for (final messageDoc in messagesQuery.docs) {
        batch.delete(messageDoc.reference);
      }

      // 2. グループの招待を削除
      final invitationsQuery = await _firestore
          .collection('group_invitations')
          .where('groupId', isEqualTo: groupId)
          .get();

      for (final invitationDoc in invitationsQuery.docs) {
        batch.delete(invitationDoc.reference);
      }

      // 3. グループドキュメントを削除
      batch.delete(_firestore.collection('groups').doc(groupId));

      // バッチ実行
      await batch.commit();

      // 4. グループ画像をStorageから削除
      final imageUrl = groupData['imageUrl'];
      if (imageUrl != null && imageUrl.startsWith('https://firebasestorage.googleapis.com')) {
        try {
          final storageRef = _storage.refFromURL(imageUrl);
          await storageRef.delete();
        } catch (e) {
        }
      }


    } catch (e) {
      throw Exception('グループの削除に失敗しました: $e');
    }
  }

  // グループ管理者チェック
  Future<bool> isGroupAdmin(String groupId) async {
    if (currentUserId == null) return false;

    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return false;

      final groupData = groupDoc.data()!;
      final admins = List<String>.from(groupData['admins'] ?? []);
      
      return admins.contains(currentUserId);
    } catch (e) {
      return false;
    }
  }

  // 招待応答処理
  Future<void> respondToInvitation(String invitationId, String groupId, bool accept) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');

    try {
      if (accept) {
        // 招待の場合は直接グループに参加できる
        String? userName;
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
          final result = await callable.call({'firebaseUid': currentUserId});
          
          if (result.data != null && result.data['exists'] == true) {
            userName = result.data['user']['name'] ?? 'ユーザー';
          }
        } catch (e) {
          userName = 'ユーザー';
        }
        
        await _directJoinGroup(groupId, userName);
      }
      
      // 招待ステータスを更新
      await _firestore.collection('group_invitations').doc(invitationId).update({
        'status': accept ? 'accepted' : 'declined',
        'respondedAt': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      throw Exception('招待への応答に失敗しました: $e');
    }
  }

  // メンバーにいいねを送る機能
  Future<void> sendLikeToUser(String targetUserId) async {
    if (currentUserId == null) throw Exception('ユーザーが認証されていません');
    if (currentUserId == targetUserId) throw Exception('自分自身にはいいねを送れません');

    try {
      // 既存のいいねをチェック
      final existingLike = await _firestore
          .collection('likes')
          .where('fromUserId', isEqualTo: currentUserId)
          .where('toUserId', isEqualTo: targetUserId)
          .get();

      if (existingLike.docs.isNotEmpty) {
        throw Exception('既にいいね済みです');
      }

      // 送信者の情報を取得
      String? senderName;
      String? senderImageUrl;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
        final result = await callable.call({'firebaseUid': currentUserId});
        
        if (result.data != null && result.data['exists'] == true) {
          senderName = result.data['user']['name'] ?? 'ユーザー';
          senderImageUrl = result.data['user']['image_url'];
        }
      } catch (e) {
        senderName = 'ユーザー';
      }

      // 受信者の情報を取得
      String? receiverName;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('getUserByFirebaseUid');
        final result = await callable.call({'firebaseUid': targetUserId});
        
        if (result.data != null && result.data['exists'] == true) {
          receiverName = result.data['user']['name'] ?? 'ユーザー';
        }
      } catch (e) {
        receiverName = 'ユーザー';
      }

      // いいねを保存
      await _firestore.collection('likes').add({
        'fromUserId': currentUserId,
        'toUserId': targetUserId,
        'fromUserName': senderName,
        'toUserName': receiverName,
        'fromUserImageUrl': senderImageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent', // sent, matched
      });

      // 相手からもいいねをもらっているかチェック（マッチング）
      final mutualLike = await _firestore
          .collection('likes')
          .where('fromUserId', isEqualTo: targetUserId)
          .where('toUserId', isEqualTo: currentUserId)
          .get();

      if (mutualLike.docs.isNotEmpty) {
        // マッチング成立
        await _createMatch(currentUserId!, targetUserId, senderName ?? 'ユーザー', receiverName ?? 'ユーザー');
        
        // 両方のいいねステータスをmatchedに更新
        for (final doc in mutualLike.docs) {
          await doc.reference.update({'status': 'matched'});
        }
        
        final newLike = await _firestore
            .collection('likes')
            .where('fromUserId', isEqualTo: currentUserId)
            .where('toUserId', isEqualTo: targetUserId)
            .get();
        
        for (final doc in newLike.docs) {
          await doc.reference.update({'status': 'matched'});
        }
      }

      // 受信者に通知を送信
      await _sendLikeNotification(
        targetUserId: targetUserId,
        senderName: senderName ?? 'ユーザー',
        isMatch: mutualLike.docs.isNotEmpty,
      );


    } catch (e) {
      rethrow;
    }
  }

  // マッチング作成
  Future<void> _createMatch(String user1Id, String user2Id, String user1Name, String user2Name) async {
    try {
      await _firestore.collection('matches').add({
        'user1Id': user1Id,
        'user2Id': user2Id,
        'user1Name': user1Name,
        'user2Name': user2Name,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageAt': null,
        'lastMessage': null,
        'isActive': true,
      });
      
    } catch (e) {
    }
  }

  // いいね通知を送信
  Future<void> _sendLikeNotification({
    required String targetUserId,
    required String senderName,
    required bool isMatch,
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(targetUserId).get();
      final userData = userDoc.data();
      final fcmToken = userData?['fcm_token'];

      if (fcmToken != null) {
        final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
        await callable.call({
          'token': fcmToken,
          'title': isMatch ? 'マッチングしました！' : 'いいねが届きました',
          'body': isMatch 
              ? '$senderName さんとマッチングしました！メッセージを送ってみましょう'
              : '$senderName さんからいいねが届きました',
          'data': {
            'type': isMatch ? 'match' : 'like',
            'sender_name': senderName,
          },
        });
      }
    } catch (e) {
    }
  }
} 