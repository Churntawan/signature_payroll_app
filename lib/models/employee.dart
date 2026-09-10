class Employee {
  final String epCode;
  final String nickname;
  final String status; // 'Active' or 'Resigned'
  final double baseSalary;
  final String payGroup; // 'Date : 1', 'Date : 10', 'Date : 20'
  final String stayOutside; // 'Yes' or 'No'
  final DateTime? startDate;
  final DateTime? resignDate;
  final String note;

  Employee({
    required this.epCode,
    required this.nickname,
    required this.status,
    required this.baseSalary,
    required this.payGroup,
    this.stayOutside = 'No',
    this.startDate,
    this.resignDate,
    this.note = '',
  });

  bool get isActive => status.toLowerCase() == 'active';

  Employee copyWith({
    String? epCode,
    String? nickname,
    String? status,
    double? baseSalary,
    String? payGroup,
    String? stayOutside,
    DateTime? startDate,
    DateTime? resignDate,
    String? note,
  }) {
    return Employee(
      epCode: epCode ?? this.epCode,
      nickname: nickname ?? this.nickname,
      status: status ?? this.status,
      baseSalary: baseSalary ?? this.baseSalary,
      payGroup: payGroup ?? this.payGroup,
      stayOutside: stayOutside ?? this.stayOutside,
      startDate: startDate ?? this.startDate,
      resignDate: resignDate ?? this.resignDate,
      note: note ?? this.note,
    );
  }
}
