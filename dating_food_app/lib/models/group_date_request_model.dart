enum GroupDateRequestStatus {
  pending('pending'),
  accepted('accepted'),
  rejected('rejected'),
  cancelled('cancelled'),
  expired('expired');

  const GroupDateRequestStatus(this.value);
  final String value;

  static GroupDateRequestStatus fromString(String value) {
    return GroupDateRequestStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => GroupDateRequestStatus.pending,
    );
  }
}

class GroupDateRequest {
  final String id;
  final String requesterId;
  final String groupId;
  final String restaurantId;
  final String? message;
  final DateTime? proposedDate1;
  final DateTime? proposedDate2;
  final DateTime? proposedDate3;
  final GroupDateRequestStatus status;
  final String? responseMessage;
  final DateTime? acceptedDate;
  final DateTime createdAt;
  final DateTime expiresAt;
  
  // レストラン情報
  final String restaurantName;
  final String? restaurantImageUrl;
  final String? restaurantCategory;
  final String? restaurantPrefecture;
  final String? restaurantNearestStation;
  final String? restaurantPriceRange;
  
  // リクエスト送信者情報
  final String requesterName;
  final String? requesterImageUrl;
  
  // 回答者リスト
  final List<GroupDateResponse> responses;

  GroupDateRequest({
    required this.id,
    required this.requesterId,
    required this.groupId,
    required this.restaurantId,
    this.message,
    this.proposedDate1,
    this.proposedDate2,
    this.proposedDate3,
    required this.status,
    this.responseMessage,
    this.acceptedDate,
    required this.createdAt,
    required this.expiresAt,
    required this.restaurantName,
    this.restaurantImageUrl,
    this.restaurantCategory,
    this.restaurantPrefecture,
    this.restaurantNearestStation,
    this.restaurantPriceRange,
    required this.requesterName,
    this.requesterImageUrl,
    this.responses = const [],
  });

  factory GroupDateRequest.fromMap(Map<String, dynamic> map) {
    return GroupDateRequest(
      id: map['id'] ?? '',
      requesterId: map['requester_id'] ?? '',
      groupId: map['group_id'] ?? '',
      restaurantId: map['restaurant_id'] ?? '',
      message: map['message'],
      proposedDate1: map['proposed_date_1'] != null 
          ? DateTime.parse(map['proposed_date_1'])
          : null,
      proposedDate2: map['proposed_date_2'] != null 
          ? DateTime.parse(map['proposed_date_2'])
          : null,
      proposedDate3: map['proposed_date_3'] != null 
          ? DateTime.parse(map['proposed_date_3'])
          : null,
      status: GroupDateRequestStatus.fromString(map['status'] ?? 'pending'),
      responseMessage: map['response_message'],
      acceptedDate: map['accepted_date'] != null 
          ? DateTime.parse(map['accepted_date'])
          : null,
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      expiresAt: map['expires_at'] != null 
          ? DateTime.parse(map['expires_at'])
          : DateTime.now().add(const Duration(days: 7)),
      restaurantName: map['restaurant_name'] ?? '',
      restaurantImageUrl: map['restaurant_image_url'],
      restaurantCategory: map['restaurant_category'],
      restaurantPrefecture: map['restaurant_prefecture'],
      restaurantNearestStation: map['restaurant_nearest_station'],
      restaurantPriceRange: map['restaurant_price_range'],
      requesterName: map['requester_name'] ?? '',
      requesterImageUrl: map['requester_image_url'],
      responses: (map['responses'] as List<dynamic>?)
          ?.map((r) => GroupDateResponse.fromMap(r))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'requester_id': requesterId,
      'group_id': groupId,
      'restaurant_id': restaurantId,
      'message': message,
      'proposed_date_1': proposedDate1?.toIso8601String(),
      'proposed_date_2': proposedDate2?.toIso8601String(),
      'proposed_date_3': proposedDate3?.toIso8601String(),
      'status': status.value,
      'response_message': responseMessage,
      'accepted_date': acceptedDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'restaurant_name': restaurantName,
      'restaurant_image_url': restaurantImageUrl,
      'restaurant_category': restaurantCategory,
      'restaurant_prefecture': restaurantPrefecture,
      'restaurant_nearest_station': restaurantNearestStation,
      'restaurant_price_range': restaurantPriceRange,
      'requester_name': requesterName,
      'requester_image_url': requesterImageUrl,
      'responses': responses.map((r) => r.toMap()).toList(),
    };
  }

  List<DateTime> get proposedDates {
    final dates = <DateTime>[];
    if (proposedDate1 != null) dates.add(proposedDate1!);
    if (proposedDate2 != null) dates.add(proposedDate2!);
    if (proposedDate3 != null) dates.add(proposedDate3!);
    return dates;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == GroupDateRequestStatus.pending && !isExpired;
  bool get isAccepted => status == GroupDateRequestStatus.accepted;
  bool get isRejected => status == GroupDateRequestStatus.rejected;
  
  // 全員が回答したかチェック
  bool hasAllResponses(List<String> memberIds) {
    final respondedIds = responses.map((r) => r.userId).toSet();
    final requiredIds = memberIds.where((id) => id != requesterId).toSet();
    return requiredIds.every((id) => respondedIds.contains(id));
  }
  
  // 承認者数
  int get acceptedCount => responses.where((r) => r.isAccepted).length;
  
  // 拒否者数
  int get rejectedCount => responses.where((r) => r.isRejected).length;
}

class GroupDateResponse {
  final String id;
  final String requestId;
  final String userId;
  final String response; // 'accept' or 'reject'
  final String? responseMessage;
  final DateTime? selectedDate;
  final DateTime createdAt;
  
  // ユーザー情報
  final String userName;
  final String? userImageUrl;

  GroupDateResponse({
    required this.id,
    required this.requestId,
    required this.userId,
    required this.response,
    this.responseMessage,
    this.selectedDate,
    required this.createdAt,
    required this.userName,
    this.userImageUrl,
  });

  factory GroupDateResponse.fromMap(Map<String, dynamic> map) {
    return GroupDateResponse(
      id: map['id'] ?? '',
      requestId: map['request_id'] ?? '',
      userId: map['user_id'] ?? '',
      response: map['response'] ?? '',
      responseMessage: map['response_message'],
      selectedDate: map['selected_date'] != null 
          ? DateTime.parse(map['selected_date'])
          : null,
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      userName: map['user_name'] ?? '',
      userImageUrl: map['user_image_url'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'request_id': requestId,
      'user_id': userId,
      'response': response,
      'response_message': responseMessage,
      'selected_date': selectedDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'user_name': userName,
      'user_image_url': userImageUrl,
    };
  }

  bool get isAccepted => response == 'accept';
  bool get isRejected => response == 'reject';
} 