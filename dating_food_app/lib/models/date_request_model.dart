class DateRequest {
  final String id;
  final String requesterId;
  final String recipientId;
  final String matchId;
  final String restaurantId;
  final String? message;
  final DateTime? proposedDate1;
  final DateTime? proposedDate2;
  final DateTime? proposedDate3;
  final DateRequestStatus status;
  final String? responseMessage;
  final DateTime? acceptedDate;
  final DateTime createdAt;
  final DateTime expiresAt;
  
  // レストラン情報
  final String restaurantName;
  final String? restaurantImageUrl;
  final String? restaurantCategory;
  final String? restaurantPrefecture;
  
  // 相手ユーザー情報
  final String partnerName;
  final String? partnerImageUrl;
  final int? partnerAge;

  DateRequest({
    required this.id,
    required this.requesterId,
    required this.recipientId,
    required this.matchId,
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
    required this.partnerName,
    this.partnerImageUrl,
    this.partnerAge,
  });

  factory DateRequest.fromMap(Map<String, dynamic> map) {
    return DateRequest(
      id: map['id'],
      requesterId: map['requester_id'],
      recipientId: map['recipient_id'],
      matchId: map['match_id'],
      restaurantId: map['restaurant_id'],
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
      status: DateRequestStatus.fromString(map['status']),
      responseMessage: map['response_message'],
      acceptedDate: map['accepted_date'] != null 
          ? DateTime.parse(map['accepted_date'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
      expiresAt: DateTime.parse(map['expires_at']),
      restaurantName: map['restaurant_name'] ?? '',
      restaurantImageUrl: map['restaurant_image_url'],
      restaurantCategory: map['restaurant_category'],
      restaurantPrefecture: map['restaurant_prefecture'],
      partnerName: map['partner_name'] ?? '',
      partnerImageUrl: map['partner_image_url'],
      partnerAge: map['partner_age'],
    );
  }

  List<DateTime> get proposedDates {
    final dates = <DateTime>[];
    if (proposedDate1 != null) dates.add(proposedDate1!);
    if (proposedDate2 != null) dates.add(proposedDate2!);
    if (proposedDate3 != null) dates.add(proposedDate3!);
    return dates;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == DateRequestStatus.pending && !isExpired;
  bool get isAccepted => status == DateRequestStatus.accepted;
  bool get isRejected => status == DateRequestStatus.rejected;

  String get statusDisplayText {
    switch (status) {
      case DateRequestStatus.pending:
        return isExpired ? '期限切れ' : '回答待ち';
      case DateRequestStatus.accepted:
        return '承認済み';
      case DateRequestStatus.rejected:
        return 'お断り';
      case DateRequestStatus.cancelled:
        return 'キャンセル';
      case DateRequestStatus.expired:
        return '期限切れ';
    }
  }

  String get statusEmoji {
    switch (status) {
      case DateRequestStatus.pending:
        return isExpired ? '⏰' : '⏳';
      case DateRequestStatus.accepted:
        return '🎉';
      case DateRequestStatus.rejected:
        return '💔';
      case DateRequestStatus.cancelled:
        return '🚫';
      case DateRequestStatus.expired:
        return '⏰';
    }
  }
}

enum DateRequestStatus {
  pending,
  accepted,
  rejected,
  cancelled,
  expired;

  static DateRequestStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return DateRequestStatus.pending;
      case 'accepted':
        return DateRequestStatus.accepted;
      case 'rejected':
        return DateRequestStatus.rejected;
      case 'cancelled':
        return DateRequestStatus.cancelled;
      case 'expired':
        return DateRequestStatus.expired;
      default:
        return DateRequestStatus.pending;
    }
  }

  String get value {
    switch (this) {
      case DateRequestStatus.pending:
        return 'pending';
      case DateRequestStatus.accepted:
        return 'accepted';
      case DateRequestStatus.rejected:
        return 'rejected';
      case DateRequestStatus.cancelled:
        return 'cancelled';
      case DateRequestStatus.expired:
        return 'expired';
    }
  }
}

class DateRequestResponse {
  final bool success;
  final String? requestId;
  final String message;
  final String? status;

  DateRequestResponse({
    required this.success,
    this.requestId,
    required this.message,
    this.status,
  });

  factory DateRequestResponse.fromMap(Map<String, dynamic> map) {
    return DateRequestResponse(
      success: map['success'] ?? false,
      requestId: map['requestId'],
      message: map['message'] ?? '',
      status: map['status'],
    );
  }
} 