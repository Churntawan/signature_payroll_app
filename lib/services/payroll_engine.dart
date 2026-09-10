import 'package:intl/intl.dart';
import '../models/employee.dart';
import '../models/payroll_record.dart';

class CycleDateRange {
  final DateTime startDate;
  final DateTime endDate;
  final DateTime payDate;

  CycleDateRange({
    required this.startDate,
    required this.endDate,
    required this.payDate,
  });

  String get formattedRange {
    final f = DateFormat('d/M/yyyy');
    return '${f.format(startDate)} - ${f.format(endDate)}';
  }
}

class PayrollEngine {
  /// คำนวณช่วงวันที่ตัดรอบสำหรับงวดและกลุ่มการจ่าย
  static CycleDateRange getCycleRange(String period, String payGroup) {
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    if (payGroup.contains('10')) {
      // รอบวันที่ 10: 11 ของเดือนก่อนหน้า -> 10 ของเดือนนี้
      final prevMonthDate = DateTime(year, month - 1, 11);
      final endDate = DateTime(year, month, 10);
      return CycleDateRange(
        startDate: prevMonthDate,
        endDate: endDate,
        payDate: endDate,
      );
    } else if (payGroup.contains('20')) {
      // รอบวันที่ 20: 21 ของเดือนก่อนหน้า -> 20 ของเดือนนี้
      final prevMonthDate = DateTime(year, month - 1, 21);
      final endDate = DateTime(year, month, 20);
      return CycleDateRange(
        startDate: prevMonthDate,
        endDate: endDate,
        payDate: endDate,
      );
    } else {
      // รอบวันที่ 1: 2 ของเดือนก่อนหน้า -> 1 ของเดือนนี้
      final prevMonthDate = DateTime(year, month - 1, 2);
      final endDate = DateTime(year, month, 1);
      return CycleDateRange(
        startDate: prevMonthDate,
        endDate: endDate,
        payDate: endDate,
      );
    }
  }

  /// คำนวณเงินเดือนของพนักงาน 1 คน พร้อมระบบ Smart Prorate
  static PayrollRecord? calculateEmployeeRecord({
    required Employee employee,
    required String period,
  }) {
    final cycle = getCycleRange(period, employee.payGroup);

    // 1. ตรวจสอบกรณีลาออกก่อนเริ่มรอบงวดนี้ -> ไม่นำมาคิด
    if (employee.resignDate != null) {
      if (employee.resignDate!.isBefore(cycle.startDate)) {
        return null;
      }
    } else if (!employee.isActive) {
      // ถ้าสถานะเป็น Resigned และไม่มีวันที่ระบุ ถือว่าพ้นสภาพแล้ว
      return null;
    }

    // 2. ตรวจสอบกรณีเริ่มงานหลังสิ้นสุดรอบงวดนี้ -> ยังไม่ถึงรอบคิดเงิน
    if (employee.startDate != null) {
      if (employee.startDate!.isAfter(cycle.endDate)) {
        return null;
      }
    }

    // 3. กำหนดวันเริ่มต้นและสิ้นสุดจริงที่ทำงานในงวดนี้
    DateTime effectiveStart = cycle.startDate;
    DateTime effectiveEnd = cycle.endDate;
    bool isProrate = false;
    List<String> reasons = [];

    final dateFormat = DateFormat('dd/MM/yyyy');

    if (employee.startDate != null && employee.startDate!.isAfter(cycle.startDate)) {
      effectiveStart = employee.startDate!;
      isProrate = true;
      reasons.add('Started: ${dateFormat.format(effectiveStart)}');
    }

    if (employee.resignDate != null && employee.resignDate!.isBefore(cycle.endDate)) {
      effectiveEnd = employee.resignDate!;
      isProrate = true;
      reasons.add('Resigned: ${dateFormat.format(effectiveEnd)}');
    }

    // 4. Calculate working days and daily rate (Base Salary / 30)
    final dailyRate = employee.baseSalary / 30.0;
    int workedDays = 30;
    double basePay = employee.baseSalary;

    if (isProrate) {
      workedDays = effectiveEnd.difference(effectiveStart).inDays + 1;
      if (workedDays < 0) workedDays = 0;
      basePay = (dailyRate * workedDays).roundToDouble();
    }

    return PayrollRecord(
      epCode: employee.epCode,
      nickname: employee.nickname,
      payGroup: employee.payGroup,
      period: period,
      cycleStartDate: cycle.startDate,
      cycleEndDate: cycle.endDate,
      payDate: cycle.payDate,
      baseSalary: employee.baseSalary,
      dailyRate: dailyRate,
      isProrate: isProrate,
      workedDays: workedDays,
      prorateReason: reasons.join(' | '),
      basePay: basePay,
      workDays: isProrate ? workedDays : 26,
      dayOff: 4,
      sickLeave: 0,
      halfDays: 0,
      otDays: 0,
    );
  }

  /// Format payslip message for LINE
  static String formatLinePayslip(PayrollRecord record) {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final df = DateFormat('dd/MM/yyyy');

    final buffer = StringBuffer();
    buffer.writeln('📋 *PAYSLIP / SALARY SLIP*');
    buffer.writeln('🏢 *SIGNATURE PAYROLL*');
    buffer.writeln('────────────────────');
    buffer.writeln('👤 Employee: ${record.nickname} (${record.epCode})');
    buffer.writeln('📅 Period: ${record.period} (${record.payGroup})');
    buffer.writeln('🗓️ Work Cycle: ${df.format(record.cycleStartDate)} - ${df.format(record.cycleEndDate)}');
    buffer.writeln('💳 Pay Date: ${df.format(record.payDate)}');
    buffer.writeln('────────────────────');
    buffer.writeln('🏖️ *Attendance & Time-off:*');
    buffer.writeln('  • Work Days: ${record.workDays} days');
    buffer.writeln('  • Day-offs: ${record.dayOff} days');
    if (record.sickLeave > 0) buffer.writeln('  • Sick Leave: ${record.sickLeave} days');
    if (record.halfDays > 0) buffer.writeln('  • Half-days: ${record.halfDays}');
    if (record.otDays > 0) buffer.writeln('  • OT Days: ${record.otDays}');
    buffer.writeln('────────────────────');

    if (record.isProrate) {
      buffer.writeln('⚠️ *Smart Prorate Calculation:*');
      buffer.writeln('   Details: ${record.prorateReason}');
      buffer.writeln('   Eligible Days: ${record.workedDays} days (@ ${currency.format(record.dailyRate)} / day)');
      buffer.writeln('💵 Prorated Pay: ${currency.format(record.basePay)} THB');
    } else {
      buffer.writeln('💵 Base Salary: ${currency.format(record.basePay)} THB');
    }

    if (record.totalExtra > 0) {
      buffer.writeln('────────────────────');
      buffer.writeln('➕ *Earnings / Allowances:*');
      if (record.overtimePay > 0) buffer.writeln('  • Overtime (OT): +${currency.format(record.overtimePay)}');
      if (record.bonusPay > 0) buffer.writeln('  • Bonus / Incentive: +${currency.format(record.bonusPay)}');
      if (record.otherExtra > 0) buffer.writeln('  • Other Extra: +${currency.format(record.otherExtra)}');
      if (record.extraNote.isNotEmpty) buffer.writeln('    (${record.extraNote})');
    }

    if (record.totalDeduction > 0) {
      buffer.writeln('────────────────────');
      buffer.writeln('➖ *Deductions:*');
      if (record.advanceDeduction > 0) buffer.writeln('  • Advance Payment: -${currency.format(record.advanceDeduction)}');
      if (record.workPermitDeduction > 0) buffer.writeln('  • Work Permit / Passport: -${currency.format(record.workPermitDeduction)}');
      if (record.otherDeduction > 0) buffer.writeln('  • Other Deductions: -${currency.format(record.otherDeduction)}');
      if (record.deductionNote.isNotEmpty) buffer.writeln('    (${record.deductionNote})');
    }

    buffer.writeln('════════════════════');
    buffer.writeln('💰 *NET PAY (ยอดโอนสุทธิ):*');
    buffer.writeln('👉 *${currency.format(record.netPay)} THB*');
    buffer.writeln('════════════════════');
    buffer.writeln('Thank you for your dedication! 🙏');

    return buffer.toString();
  }
}
