class SalaryRecord {
  final String id;
  final String epCode;
  final String effectivePeriod; // Format: 'YYYY-MM' e.g. '2026-10'
  final double baseSalary;
  final double? previousSalary;
  final String reason;
  final DateTime createdAt;
  final String createdByName;

  const SalaryRecord({
    required this.id,
    required this.epCode,
    required this.effectivePeriod,
    required this.baseSalary,
    this.previousSalary,
    this.reason = '',
    required this.createdAt,
    this.createdByName = 'Admin',
  });

  /// The difference from previous salary (if known)
  double? get salaryDiff => previousSalary != null ? (baseSalary - previousSalary!) : null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ep_code': epCode,
      'effective_period': effectivePeriod,
      'base_salary': baseSalary,
      'previous_salary': previousSalary,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdByName,
    };
  }

  factory SalaryRecord.fromJson(Map<String, dynamic> json) {
    return SalaryRecord(
      id: json['id']?.toString() ?? '',
      epCode: json['ep_code']?.toString() ?? '',
      effectivePeriod: json['effective_period']?.toString() ?? '',
      baseSalary: (json['base_salary'] as num?)?.toDouble() ?? 0.0,
      previousSalary: (json['previous_salary'] as num?)?.toDouble(),
      reason: json['reason']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      createdByName: json['created_by']?.toString() ?? 'Admin',
    );
  }

  SalaryRecord copyWith({
    String? id,
    String? epCode,
    String? effectivePeriod,
    double? baseSalary,
    double? previousSalary,
    String? reason,
    DateTime? createdAt,
    String? createdByName,
  }) {
    return SalaryRecord(
      id: id ?? this.id,
      epCode: epCode ?? this.epCode,
      effectivePeriod: effectivePeriod ?? this.effectivePeriod,
      baseSalary: baseSalary ?? this.baseSalary,
      previousSalary: previousSalary ?? this.previousSalary,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      createdByName: createdByName ?? this.createdByName,
    );
  }
}
