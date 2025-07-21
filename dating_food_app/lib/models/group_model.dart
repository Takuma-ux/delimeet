import 'package:cloud_firestore/cloud_firestore.dart';

// グループモデル
class Group {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String createdBy;
  final List<String> members;
  final List<String> admins;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageBy;
  final bool isPrivate;
  final int maxMembers;
  final String? category;
  final String? prefecture;
  final String? nearestStation;
  final List<String>? tags; // ハッシュタグ
  
  // 募集作成機能用の新しいフィールド
  final String? groupType; // 'general' または 'restaurant_meetup'
  final Map<String, dynamic>? restaurantInfo; // レストラン情報
  final DateTime? eventDateTime; // 開催開始日時
  final DateTime? eventEndDateTime; // 開催終了日時
  final int? minMembers; // 最小参加人数

  Group({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
    required this.createdBy,
    required this.members,
    required this.admins,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageBy,
    this.isPrivate = false,
    this.maxMembers = 100,
    this.category,
    this.prefecture,
    this.nearestStation,
    this.tags,
    this.groupType = 'general', // デフォルトは一般的なグループ
    this.restaurantInfo,
    this.eventDateTime,
    this.eventEndDateTime,
    this.minMembers,
  });

  factory Group.fromMap(Map<String, dynamic> data, String id) {
    return Group(
      id: id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'],
      createdBy: data['createdBy'] ?? '',
      members: List<String>.from(data['members'] ?? []),
      admins: List<String>.from(data['admins'] ?? []),
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null 
          ? (data['updatedAt'] as Timestamp).toDate() 
          : DateTime.now(),
      lastMessage: data['lastMessage'],
      lastMessageAt: data['lastMessageAt'] != null 
          ? (data['lastMessageAt'] as Timestamp).toDate() 
          : null,
      lastMessageBy: data['lastMessageBy'],
      isPrivate: data['isPrivate'] ?? false,
      maxMembers: data['maxMembers'] ?? 100,
      category: data['category'],
      prefecture: data['prefecture'],
      nearestStation: data['nearestStation'],
      tags: data['tags'] != null ? List<String>.from(data['tags']) : null,
      groupType: data['groupType'] ?? 'general',
      restaurantInfo: data['restaurantInfo'] != null 
          ? Map<String, dynamic>.from(data['restaurantInfo']) 
          : null,
      eventDateTime: data['eventDateTime'] != null 
          ? (data['eventDateTime'] as Timestamp).toDate() 
          : null,
      eventEndDateTime: data['eventEndDateTime'] != null 
          ? (data['eventEndDateTime'] as Timestamp).toDate() 
          : null,
      minMembers: data['minMembers'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'createdBy': createdBy,
      'members': members,
      'admins': admins,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt != null 
          ? Timestamp.fromDate(lastMessageAt!) 
          : null,
      'lastMessageBy': lastMessageBy,
      'isPrivate': isPrivate,
      'maxMembers': maxMembers,
      'category': category,
      'prefecture': prefecture,
      'nearestStation': nearestStation,
      'tags': tags,
      'groupType': groupType,
      'restaurantInfo': restaurantInfo,
      'eventDateTime': eventDateTime != null 
          ? Timestamp.fromDate(eventDateTime!) 
          : null,
      'eventEndDateTime': eventEndDateTime != null 
          ? Timestamp.fromDate(eventEndDateTime!) 
          : null,
      'minMembers': minMembers,
    };
  }

  Group copyWith({
    String? name,
    String? description,
    String? imageUrl,
    List<String>? members,
    List<String>? admins,
    DateTime? updatedAt,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastMessageBy,
    bool? isPrivate,
    int? maxMembers,
    String? category,
    String? prefecture,
    String? nearestStation,
    List<String>? tags,
    String? groupType,
    Map<String, dynamic>? restaurantInfo,
    DateTime? eventDateTime,
    DateTime? eventEndDateTime,
    int? minMembers,
  }) {
    return Group(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      createdBy: createdBy,
      members: members ?? this.members,
      admins: admins ?? this.admins,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageBy: lastMessageBy ?? this.lastMessageBy,
      isPrivate: isPrivate ?? this.isPrivate,
      maxMembers: maxMembers ?? this.maxMembers,
      category: category ?? this.category,
      prefecture: prefecture ?? this.prefecture,
      nearestStation: nearestStation ?? this.nearestStation,
      tags: tags ?? this.tags,
      groupType: groupType ?? this.groupType,
      restaurantInfo: restaurantInfo ?? this.restaurantInfo,
      eventDateTime: eventDateTime ?? this.eventDateTime,
      eventEndDateTime: eventEndDateTime ?? this.eventEndDateTime,
      minMembers: minMembers ?? this.minMembers,
    );
  }
}

// グループメッセージモデル
class GroupMessage {
  final String id;
  final String groupId;
  final String senderId; // Firebase UID
  final String? senderUuid; // usersテーブルのid（UUID）
  final String senderName;
  final String? senderImageUrl;
  final String message;
  final MessageType type;
  final String? imageUrl;
  final DateTime timestamp;
  final bool isDeleted;
  final String? replyToId;
  final Map<String, bool> readBy;
  final Map<String, dynamic>? dateRequestData; // デートリクエストデータ
  final String? relatedDateRequestId; // 関連するデートリクエストID
  final Map<String, dynamic>? restaurantVotingData; // 店舗投票データ
  final Map<String, dynamic>? restaurantVotingResponseData; // 店舗投票回答データ
  final String? relatedRestaurantVotingId; // 関連する店舗投票ID

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.senderUuid,
    required this.senderName,
    this.senderImageUrl,
    required this.message,
    required this.type,
    this.imageUrl,
    required this.timestamp,
    this.isDeleted = false,
    this.replyToId,
    required this.readBy,
    this.dateRequestData,
    this.relatedDateRequestId,
    this.restaurantVotingData,
    this.restaurantVotingResponseData,
    this.relatedRestaurantVotingId,
  });

  factory GroupMessage.fromMap(Map<String, dynamic> data, String id) {
    return GroupMessage(
      id: id,
      groupId: data['groupId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderUuid: data['senderUuid'],
      senderName: data['senderName'] ?? '',
      senderImageUrl: data['senderImageUrl'],
      message: data['message'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.toString() == 'MessageType.${data['type']}',
        orElse: () => MessageType.text,
      ),
      imageUrl: data['imageUrl'],
      timestamp: data['timestamp'] != null 
          ? (data['timestamp'] as Timestamp).toDate() 
          : DateTime.now(),
      isDeleted: data['isDeleted'] ?? false,
      replyToId: data['replyToId'],
      readBy: Map<String, bool>.from(data['readBy'] ?? {}),
      dateRequestData: data['dateRequestData'] != null 
          ? Map<String, dynamic>.from(data['dateRequestData']) 
          : (data['dateDecisionData'] != null 
              ? Map<String, dynamic>.from(data['dateDecisionData'])
              : null),
      relatedDateRequestId: data['relatedDateRequestId'],
      restaurantVotingData: data['restaurantVotingData'] != null 
          ? Map<String, dynamic>.from(data['restaurantVotingData']) 
          : (data['restaurantDecisionData'] != null 
              ? Map<String, dynamic>.from(data['restaurantDecisionData'])
              : null),
      restaurantVotingResponseData: data['restaurantVotingResponseData'] != null 
          ? Map<String, dynamic>.from(data['restaurantVotingResponseData']) 
          : null,
      relatedRestaurantVotingId: data['relatedRestaurantVotingId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'senderId': senderId,
      'senderUuid': senderUuid,
      'senderName': senderName,
      'senderImageUrl': senderImageUrl,
      'message': message,
      'type': type.toString().split('.').last,
      'imageUrl': imageUrl,
      'timestamp': Timestamp.fromDate(timestamp),
      'isDeleted': isDeleted,
      'replyToId': replyToId,
      'readBy': readBy,
      'dateRequestData': dateRequestData,
      'relatedDateRequestId': relatedDateRequestId,
      'restaurantVotingData': restaurantVotingData,
      'restaurantVotingResponseData': restaurantVotingResponseData,
      'relatedRestaurantVotingId': relatedRestaurantVotingId,
    };
  }
}

// メッセージタイプ列挙型
enum MessageType {
  text,
  image,
  system,
  notification,
  group_date_request,
  group_date_response,
  date_decision,
  restaurant_voting,
  restaurant_voting_response,
  restaurant_decision,
}

// グループメンバーモデル
class GroupMember {
  final String userId;
  final String displayName;
  final String? imageUrl;
  final DateTime joinedAt;
  final GroupRole role;
  final bool isActive;
  final DateTime? lastSeen;

  GroupMember({
    required this.userId,
    required this.displayName,
    this.imageUrl,
    required this.joinedAt,
    required this.role,
    this.isActive = true,
    this.lastSeen,
  });

  factory GroupMember.fromMap(Map<String, dynamic> data) {
    return GroupMember(
      userId: data['userId'] ?? '',
      displayName: data['displayName'] ?? '',
      imageUrl: data['imageUrl'],
      joinedAt: data['joinedAt'] != null 
          ? (data['joinedAt'] as Timestamp).toDate() 
          : DateTime.now(),
      role: GroupRole.values.firstWhere(
        (e) => e.toString() == 'GroupRole.${data['role']}',
        orElse: () => GroupRole.member,
      ),
      isActive: data['isActive'] ?? true,
      lastSeen: data['lastSeen'] != null 
          ? (data['lastSeen'] as Timestamp).toDate() 
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'imageUrl': imageUrl,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'role': role.toString().split('.').last,
      'isActive': isActive,
      'lastSeen': lastSeen != null 
          ? Timestamp.fromDate(lastSeen!) 
          : null,
    };
  }
}

// グループメンバーの役割
enum GroupRole {
  admin,    // 管理者
  member,   // 一般メンバー
}

// グループのステータス（招待中/参加済み）
enum GroupStatus {
  member,   // 参加済みメンバー
  invited,  // 招待中
}

// 参加申請のステータス
enum JoinRequestStatus {
  pending,   // 申請中
  approved,  // 承認済み
  rejected,  // 拒否済み
}

// グループ参加申請モデル
class GroupJoinRequest {
  final String id;
  final String groupId;
  final String groupName;
  final String applicantId;
  final String applicantName;
  final String? applicantImageUrl;
  final DateTime createdAt;
  final JoinRequestStatus status;
  final DateTime? respondedAt;
  final String? message; // 申請時のメッセージ

  GroupJoinRequest({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.applicantId,
    required this.applicantName,
    this.applicantImageUrl,
    required this.createdAt,
    required this.status,
    this.respondedAt,
    this.message,
  });

  factory GroupJoinRequest.fromMap(Map<String, dynamic> data, String id) {
    return GroupJoinRequest(
      id: id,
      groupId: data['groupId'] ?? '',
      groupName: data['groupName'] ?? '',
      applicantId: data['applicantId'] ?? '',
      applicantName: data['applicantName'] ?? '',
      applicantImageUrl: data['applicantImageUrl'],
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      status: _parseJoinRequestStatus(data['status']),
      respondedAt: data['respondedAt'] != null 
          ? (data['respondedAt'] as Timestamp).toDate() 
          : null,
      message: data['message'],
    );
  }

  static JoinRequestStatus _parseJoinRequestStatus(dynamic status) {
    if (status == null) return JoinRequestStatus.pending;
    
    try {
      return JoinRequestStatus.values.firstWhere(
        (e) => e.toString() == 'JoinRequestStatus.$status',
        orElse: () => JoinRequestStatus.pending,
      );
    } catch (e) {
      return JoinRequestStatus.pending;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'groupName': groupName,
      'applicantId': applicantId,
      'applicantName': applicantName,
      'applicantImageUrl': applicantImageUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status.toString().split('.').last,
      'respondedAt': respondedAt != null 
          ? Timestamp.fromDate(respondedAt!) 
          : null,
      'message': message,
    };
  }
}

// グループとそのステータスを組み合わせたクラス
class GroupWithStatus {
  final Group group;
  final GroupStatus status;
  final String? invitationId; // 招待IDのストア（招待中の場合のみ）

  GroupWithStatus({
    required this.group,
    required this.status,
    this.invitationId,
  });

  factory GroupWithStatus.fromJson(Map<String, dynamic> json) {
    return GroupWithStatus(
      group: Group.fromMap(json['group'] as Map<String, dynamic>, json['group']['id'] as String),
      status: GroupStatus.values.firstWhere(
        (e) => e.toString() == 'GroupStatus.${json['status']}',
        orElse: () => GroupStatus.member,
      ),
      invitationId: json['invitationId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'group': group.toMap()..['id'] = group.id,
      'status': status.toString().split('.').last,
      'invitationId': invitationId,
    };
  }
} 