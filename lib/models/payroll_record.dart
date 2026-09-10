class PayrollRecord {
  final String epCode;
  final String nickname;
  final String payGroup;
  final String period; // e.g. '2025-01'
  final DateTime cycleStartDate;
  final DateTime cycleEndDate;
  final DateTime payDate;
  
  final double baseSalary;
  final double dailyRate; // baseSalary / 30
  final bool isProrate;
  final int workedDays;
  final String prorateReason; // e.g. 'เข้างานใหม่วันที่ 15/01/2025' or 'ลาออกวันที่ 05/01/2025'
  
  final double basePay; // full baseSalary or prorated amount
  double overtimePay;
  double bonusPay;
  double otherExtra;
  String extraNote;
  
  // Attendance & Leave details
  int workDays;
  int dayOff;
  int sickLeave;
  int halfDays;
  int otDays;

  double advanceDeduction;
  double workPermitDeduction;
  double otherDeduction;
  String deductionNote;
  
  String status; // 'Draft', 'Approved', 'Paid'

  PayrollRecord({
    required this.epCode,
    required this.nickname,
    required this.payGroup,
    required this.period,
    required this.cycleStartDate,
    required this.cycleEndDate,
    required this.payDate,
    required this.baseSalary,
    required this.dailyRate,
    required this.isProrate,
    required this.workedDays,
    this.prorateReason = '',
    required this.basePay,
    this.overtimePay = 0,
    this.bonusPay = 0,
    this.otherExtra = 0,
    this.extraNote = '',
    this.workDays = 26,
    this.dayOff = 4,
    this.sickLeave = 0,
    this.halfDays = 0,
    this.otDays = 0,
    this.advanceDeduction = 0,
    this.workPermitDeduction = 0,
    this.otherDeduction = 0,
    this.deductionNote = '',
    this.status = 'Approved',
  });

  double get totalExtra => overtimePay + bonusPay + otherExtra;
  double get totalDeduction => advanceDeduction + workPermitDeduction + otherDeduction;
  double get netPay => (basePay + totalExtra - totalDeduction);
}
