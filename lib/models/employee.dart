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

  /// Get list of preferred weekday day-offs (1 = Mon, 7 = Sun)
  List<int> get preferredDayOffs {
    if (note.isEmpty) return [];
    final match = RegExp(r'\[DayOff:([0-9,]+)\]').firstMatch(note);
    if (match != null) {
      final daysStr = match.group(1);
      if (daysStr != null && daysStr.isNotEmpty) {
        return daysStr
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
      }
    }
    return [];
  }

  /// Create a new note string with updated preferred day-offs tag
  String withPreferredDayOffs(List<int> days) {
    var clean = note.replaceAll(RegExp(r'\[DayOff:[0-9,]*\]'), '').trim();
    if (days.isEmpty) return clean;
    days.sort();
    final tag = '[DayOff:${days.join(',')}]';
    return clean.isEmpty ? tag : '$clean $tag';
  }

  /// Return a new Employee instance with updated preferred day-offs
  Employee copyWithPreferredDayOffs(List<int> days) {
    return copyWith(note: withPreferredDayOffs(days));
  }
}
