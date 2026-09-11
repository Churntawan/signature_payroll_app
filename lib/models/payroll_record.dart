class PayrollRecord {
  final String epCode;
  final String nickname;
  final String payGroup;
  final String period; // e.g. '2025-01'
  final DateTime cycleStartDate;
  final DateTime cycleEndDate;
  final DateTime payDate;
  
  final double baseSalary;
  final double dailyRate; // baseSalary / 30 (or daily rate for daily wage)
  final bool isProrate;
  final int workedDays;
  final String prorateReason; // e.g. 'เข้างานใหม่วันที่ 15/01/2025' or 'ลาออกวันที่ 05/01/2025'
  final String wageType; // 'Monthly' or 'Daily'
  
  double basePay; // full baseSalary or prorated amount or (dailyRate * workDays)
  double overtimePay;
  double bonusPay;
  double otherExtra;
  String extraNote;
  
  // Housing Allowance
  double housingAllowance;
  String housingAllowanceNote;

  // Attendance & Leave details
  int workDays;
  int dayOff;
  int sickLeave;
  int halfDays;
  int otDays;
  List<Map<String, dynamic>> attendanceDetails;

  // Excess Day-offs deduction (over 4 days)
  int excessDayOffDays;
  double excessDayOffDeduction;

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
    this.wageType = 'Monthly',
    required this.basePay,
    this.overtimePay = 0,
    this.bonusPay = 0,
    this.otherExtra = 0,
    this.extraNote = '',
    this.housingAllowance = 0,
    this.housingAllowanceNote = '',
    this.workDays = 26,
    this.dayOff = 4,
    this.sickLeave = 0,
    this.halfDays = 0,
    this.otDays = 0,
    this.attendanceDetails = const [],
    this.excessDayOffDays = 0,
    this.excessDayOffDeduction = 0,
    this.advanceDeduction = 0,
    this.workPermitDeduction = 0,
    this.otherDeduction = 0,
    this.deductionNote = '',
    this.status = 'Approved',
  });

  double get totalExtra => overtimePay + bonusPay + otherExtra + housingAllowance;
  double get totalDeduction => advanceDeduction + workPermitDeduction + otherDeduction + excessDayOffDeduction;
  double get netPay => (basePay + totalExtra - totalDeduction);

  // Helper getters for specific leave categories
  List<Map<String, dynamic>> get dayOffLogs => attendanceDetails.where((a) {
        final cat = (a['category'] ?? a['status'])?.toString();
        return cat == 'Day-off' || cat == 'OFF';
      }).toList();

  List<Map<String, dynamic>> get sickLogs => attendanceDetails.where((a) {
        final cat = (a['category'] ?? a['status'])?.toString();
        return cat == 'Sick' || cat == 'Sick Leave';
      }).toList();

  List<Map<String, dynamic>> get halfDayLogs => attendanceDetails.where((a) {
        final cat = (a['category'] ?? a['status'])?.toString();
        return cat == 'Half-day' || cat == 'Half';
      }).toList();

  List<Map<String, dynamic>> get otDayLogs => attendanceDetails.where((a) {
        final cat = (a['category'] ?? a['status'])?.toString();
        return cat == 'OT Days' || cat == 'OT';
      }).toList();

  List<Map<String, dynamic>> get workDayLogs => attendanceDetails.where((a) {
        final cat = (a['category'] ?? a['status'])?.toString();
        return cat == 'Work Days' || cat == 'Work' || cat == 'Work Day';
      }).toList();

  List<Map<String, dynamic>> get otherLeaveLogs => attendanceDetails.where((a) {
        final cat = (a['category'] ?? a['status'])?.toString();
        return !['Day-off', 'OFF', 'Sick', 'Sick Leave', 'Half-day', 'Half', 'OT Days', 'OT', 'Work Days'].contains(cat);
      }).toList();
}
