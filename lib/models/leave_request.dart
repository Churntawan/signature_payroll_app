enum LeaveRequestStatus {
  pending('Pending', 'รออนุมัติ', 'စိစစ်ဆဲ'),
  approved('Approved', 'อนุมัติแล้ว', 'ခွင့်ပြုပြီး'),
  rejected('Rejected', 'ไม่อนุมัติ', 'ငြင်းပယ်သည်');

  final String labelEn;
  final String labelTh;
  final String labelMy;

  const LeaveRequestStatus(this.labelEn, this.labelTh, this.labelMy);

  static LeaveRequestStatus fromString(String? val) {
    if (val == 'Approved' || val == 'approved') return LeaveRequestStatus.approved;
    if (val == 'Rejected' || val == 'rejected' || val == 'Ignored') return LeaveRequestStatus.rejected;
    return LeaveRequestStatus.pending;
  }
}

class LeaveRequest {
  final String id;
  final String epCode;
  final String nickname;
  final DateTime date;
  final String category; // 'Day-off' or 'Sick'
  final String note;
  LeaveRequestStatus status;
  final DateTime createdAt;
  DateTime? reviewedAt;
  String? rejectionReason;

  LeaveRequest({
    required this.id,
    required this.epCode,
    required this.nickname,
    required this.date,
    required this.category,
    this.note = '',
    this.status = LeaveRequestStatus.pending,
    required this.createdAt,
    this.reviewedAt,
    this.rejectionReason,
  });

  String get dateStr {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ep_code': epCode,
      'nickname': nickname,
      'date': dateStr,
      'category': category,
      'note': note,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'rejection_reason': rejectionReason,
    };
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    DateTime reqDate;
    try {
      reqDate = DateTime.parse(json['date']?.toString() ?? '');
    } catch (_) {
      reqDate = DateTime.now().add(const Duration(days: 1));
    }

    DateTime cAt;
    try {
      cAt = DateTime.parse(json['created_at']?.toString() ?? '');
    } catch (_) {
      cAt = DateTime.now();
    }

    DateTime? rAt;
    if (json['reviewed_at'] != null) {
      try {
        rAt = DateTime.parse(json['reviewed_at'].toString());
      } catch (_) {}
    }

    return LeaveRequest(
      id: json['id']?.toString() ?? 'REQ-${DateTime.now().millisecondsSinceEpoch}',
      epCode: json['ep_code']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      date: reqDate,
      category: json['category']?.toString() ?? 'Day-off',
      note: json['note']?.toString() ?? '',
      status: LeaveRequestStatus.fromString(json['status']?.toString()),
      createdAt: cAt,
      reviewedAt: rAt,
      rejectionReason: json['rejection_reason']?.toString(),
    );
  }
}
