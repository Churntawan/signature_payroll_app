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
      reasons.add('เริ่มงานใหม่ ${dateFormat.format(effectiveStart)}');
    }

    if (employee.resignDate != null && employee.resignDate!.isBefore(cycle.endDate)) {
      effectiveEnd = employee.resignDate!;
      isProrate = true;
      reasons.add('ลาออกวันที่ ${dateFormat.format(effectiveEnd)}');
    }

    // 4. คำนวณวันทำงานและอัตราเฉลี่ยต่อวัน (เงินเดือนฐาน / 30)
    final dailyRate = employee.baseSalary / 30.0;
    int workedDays = 30;
    double basePay = employee.baseSalary;

    if (isProrate) {
      // จำนวนวันจริงที่ทำงาน
      workedDays = effectiveEnd.difference(effectiveStart).inDays + 1;
      if (workedDays < 0) workedDays = 0;
      // ปัดเศษให้เป็นจำนวนเต็มเพื่อง่ายต่อการจ่ายจริง
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
    );
  }

  /// สร้างข้อความสำหรับคัดลอกส่งเข้า LINE
  static String formatLinePayslip(PayrollRecord record) {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final df = DateFormat('dd/MM/yyyy');

    final buffer = StringBuffer();
    buffer.writeln('📋 *ใบแจ้งเงินเดือน / PAYSLIP*');
    buffer.writeln('🏢 *SIGNATURE PAYROLL*');
    buffer.writeln('────────────────────');
    buffer.writeln('👤 พนักงาน: ${record.nickname} (${record.epCode})');
    buffer.writeln('📅 งวด: ${record.period} (${record.payGroup})');
    buffer.writeln('🗓️ รอบการทำงาน: ${df.format(record.cycleStartDate)} - ${df.format(record.cycleEndDate)}');
    buffer.writeln('💳 กำหนดจ่าย: ${df.format(record.payDate)}');
    buffer.writeln('────────────────────');

    if (record.isProrate) {
      buffer.writeln('⚠️ *คิดตามสัดส่วน (Prorate)*');
      buffer.writeln('   เหตุผล: ${record.prorateReason}');
      buffer.writeln('   วันทำงานจริง: ${record.workedDays} วัน (วันละ ${currency.format(record.dailyRate)} บ.)');
      buffer.writeln('💵 ค่าจ้างตามสัดส่วน: ${currency.format(record.basePay)} บาท');
    } else {
      buffer.writeln('💵 เงินเดือนฐาน: ${currency.format(record.basePay)} บาท');
    }

    if (record.totalExtra > 0) {
      buffer.writeln('────────────────────');
      buffer.writeln('➕ *รายได้เสริม / เงินเพิ่ม:*');
      if (record.overtimePay > 0) buffer.writeln('  • ค่าล่วงเวลา (OT): +${currency.format(record.overtimePay)}');
      if (record.bonusPay > 0) buffer.writeln('  • เบี้ยขยัน / โบนัส: +${currency.format(record.bonusPay)}');
      if (record.otherExtra > 0) buffer.writeln('  • รายได้พิเศษอื่นๆ: +${currency.format(record.otherExtra)}');
      if (record.extraNote.isNotEmpty) buffer.writeln('    (${record.extraNote})');
    }

    if (record.totalDeduction > 0) {
      buffer.writeln('────────────────────');
      buffer.writeln('➖ *รายการหัก:*');
      if (record.advanceDeduction > 0) buffer.writeln('  • เงินเบิกล่วงหน้า: -${currency.format(record.advanceDeduction)}');
      if (record.workPermitDeduction > 0) buffer.writeln('  • ค่าเอกสาร/Work Permit: -${currency.format(record.workPermitDeduction)}');
      if (record.otherDeduction > 0) buffer.writeln('  • หักอื่นๆ: -${currency.format(record.otherDeduction)}');
      if (record.deductionNote.isNotEmpty) buffer.writeln('    (${record.deductionNote})');
    }

    buffer.writeln('════════════════════');
    buffer.writeln('💰 *ยอดโอนสุทธิ (NET PAY):*');
    buffer.writeln('👉 *${currency.format(record.netPay)} บาท*');
    buffer.writeln('════════════════════');
    buffer.writeln('ขอบคุณสำหรับการทำงานอย่างเต็มที่ครับ 🙏');

    return buffer.toString();
  }
}
