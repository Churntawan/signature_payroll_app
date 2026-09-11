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

  /// Check if employee is paid on daily wage basis
  bool get isDailyWage => note.contains('[Wage:Daily]');
  String get wageType => isDailyWage ? 'Daily' : 'Monthly';

  /// Housing allowance amount (defaults to 1000.0 if stayOutside is Yes, unless custom tag is set)
  double get housingAllowance {
    if (stayOutside.toLowerCase() != 'yes') return 0.0;
    final match = RegExp(r'\[Housing:([0-9.]+)\]').firstMatch(note);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '') ?? 1000.0;
    }
    return 1000.0;
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

  /// Create a new note string with updated wage type and housing allowance tags
  String withWelfareSettings({String? wageType, double? housingAllowance}) {
    var clean = note
        .replaceAll(RegExp(r'\[Wage:(Monthly|Daily)\]'), '')
        .replaceAll(RegExp(r'\[Housing:[0-9.]+\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final List<String> tags = [];
    final finalWage = wageType ?? this.wageType;
    if (finalWage == 'Daily') {
      tags.add('[Wage:Daily]');
    }

    final finalHousing = housingAllowance ?? this.housingAllowance;
    if (finalHousing > 0) {
      tags.add('[Housing:${finalHousing.toStringAsFixed(0)}]');
    }

    if (tags.isEmpty) return clean;
    final tagStr = tags.join(' ');
    return clean.isEmpty ? tagStr : '$clean $tagStr';
  }

  /// Return a new Employee instance with updated welfare settings
  Employee copyWithWelfareSettings({String? wageType, double? housingAllowance, String? stayOutside}) {
    return copyWith(
      stayOutside: stayOutside,
      note: withWelfareSettings(wageType: wageType, housingAllowance: housingAllowance),
    );
  }
}

