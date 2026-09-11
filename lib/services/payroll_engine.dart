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

    // 4. Calculate working days and daily rate
    final isDaily = employee.isDailyWage;
    final dailyRate = isDaily ? employee.dailyWageRate : (employee.baseSalary / 30.0);
    int workedDays = 30;
    double basePay = employee.baseSalary;

    if (isDaily) {
      // Daily wage employee: initial default 26 days or prorated days
      workedDays = isProrate ? effectiveEnd.difference(effectiveStart).inDays + 1 : 26;
      if (workedDays < 0) workedDays = 0;
      basePay = (dailyRate * workedDays).roundToDouble();
    } else if (isProrate) {
      workedDays = effectiveEnd.difference(effectiveStart).inDays + 1;
      if (workedDays < 0) workedDays = 0;
      basePay = (dailyRate * workedDays).roundToDouble();
    }

    // 5. Housing allowance calculation & qualification checks
    double housingAllowance = 0.0;
    String housingAllowanceNote = '';

    if (employee.stayOutside.toLowerCase() == 'yes') {
      final configuredAmount = employee.housingAllowance;

      // Condition 1: Must have worked for at least 1 month before current cycle (starts the next month)
      bool reachedOneMonth = true;
      if (employee.startDate != null) {
        final oneMonthAnniversary = DateTime(
          employee.startDate!.year,
          employee.startDate!.month + 1,
          employee.startDate!.day,
        );
        // Eligible starting next month -> oneMonthAnniversary must be on or before current cycle start
        if (oneMonthAnniversary.isAfter(cycle.startDate)) {
          reachedOneMonth = false;
        }
      }

      // Condition 2: Forfeited if resigned mid-cycle
      bool resignedMidCycle = false;
      if (employee.resignDate != null && employee.resignDate!.isBefore(cycle.endDate)) {
        resignedMidCycle = true;
      }

      if (!reachedOneMonth) {
        housingAllowance = 0.0;
        housingAllowanceNote = 'ยังไม่ครบอายุงาน 1 เดือน (เริ่มได้งวดถัดไป)';
      } else if (resignedMidCycle) {
        housingAllowance = 0.0;
        housingAllowanceNote = 'ถูกตัดสิทธิ์เนื่องจากลาออกระหว่างงวด';
      } else {
        housingAllowance = configuredAmount;
        housingAllowanceNote = 'ได้รับสิทธิ์สวัสดิการค่าห้องพัก';
      }
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
      wageType: isDaily ? 'Daily' : 'Monthly',
      basePay: basePay,
      housingAllowance: housingAllowance,
      housingAllowanceNote: housingAllowanceNote,
      workDays: isProrate ? workedDays : 26,
      dayOff: 4,
      sickLeave: 0,
      halfDays: 0,
      otDays: 0,
    );
  }

  static String _formatShortDate(String? dStr) {
    if (dStr == null || dStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dStr);
      return DateFormat('dd/MM').format(d);
    } catch (_) {
      return dStr;
    }
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
    buffer.writeln('🏖️ *Attendance & Time-off (สถิติและวันหยุด/วันลา):*');
    buffer.writeln('  • Work Days: ${record.workDays} days');

    final offDates = record.dayOffLogs
        .map((l) => _formatShortDate(l['date']?.toString()))
        .where((s) => s.isNotEmpty)
        .join(', ');
    buffer.writeln('  • Day-offs: ${record.dayOff} days${offDates.isNotEmpty ? ' ($offDates)' : ''}');

    if (record.sickLeave > 0 || record.sickLogs.isNotEmpty) {
      final sickDates = record.sickLogs.map((l) {
        final d = _formatShortDate(l['date']?.toString());
        final note = l['note']?.toString() ?? '';
        return note.isNotEmpty ? '$d [$note]' : d;
      }).where((s) => s.isNotEmpty).join(', ');
      final count = record.sickLeave > 0 ? record.sickLeave : record.sickLogs.length;
      buffer.writeln('  • Sick Leave: $count days${sickDates.isNotEmpty ? ' ($sickDates)' : ''}');
    }
    if (record.halfDays > 0 || record.halfDayLogs.isNotEmpty) {
      final halfDates = record.halfDayLogs
          .map((l) => _formatShortDate(l['date']?.toString()))
          .where((s) => s.isNotEmpty)
          .join(', ');
      final count = record.halfDays > 0 ? record.halfDays : record.halfDayLogs.length;
      buffer.writeln('  • Half-days: $count${halfDates.isNotEmpty ? ' ($halfDates)' : ''}');
    }
    if (record.otDays > 0 || record.otDayLogs.isNotEmpty) {
      final otDates = record.otDayLogs
          .map((l) => _formatShortDate(l['date']?.toString()))
          .where((s) => s.isNotEmpty)
          .join(', ');
      final count = record.otDays > 0 ? record.otDays : record.otDayLogs.length;
      buffer.writeln('  • OT Days: $count${otDates.isNotEmpty ? ' ($otDates)' : ''}');
    }
    final otherLogs = record.otherLeaveLogs;
    if (otherLogs.isNotEmpty) {
      final otherDates = otherLogs.map((l) {
        final cat = l['category'] ?? 'Leave';
        final d = _formatShortDate(l['date']?.toString());
        final note = l['note']?.toString() ?? '';
        return '$cat: $d${note.isNotEmpty ? ' [$note]' : ''}';
      }).join(', ');
      buffer.writeln('  • Other Leaves: $otherDates');
    }
    buffer.writeln('────────────────────');

    if (record.wageType == 'Daily') {
      buffer.writeln('💵 Daily Wage (ค่าจ้างรายวัน): ฿${currency.format(record.dailyRate)} × ${record.workDays} วัน = ${currency.format(record.basePay)} THB');
    } else if (record.isProrate) {
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
      if (record.housingAllowance > 0) buffer.writeln('  • Housing Allowance (ค่าห้องพัก): +${currency.format(record.housingAllowance)}');
      if (record.otherExtra > 0) buffer.writeln('  • Other Extra: +${currency.format(record.otherExtra)}');
      if (record.extraNote.isNotEmpty) buffer.writeln('    (${record.extraNote})');
    }

    if (record.totalDeduction > 0) {
      buffer.writeln('────────────────────');
      buffer.writeln('➖ *Deductions:*');
      if (record.excessDayOffDeduction > 0) buffer.writeln('  • Excess Day-off (หยุดเกินโควตา ${record.excessDayOffDays} วัน): -${currency.format(record.excessDayOffDeduction)}');
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
