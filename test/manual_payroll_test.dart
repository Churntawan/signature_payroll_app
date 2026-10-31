import 'package:flutter_test/flutter_test.dart';
import 'package:signature_payroll_app/models/payroll_record.dart';
import 'package:signature_payroll_app/services/manual_payroll_service.dart';
import 'package:signature_payroll_app/services/session_storage.dart';

void main() {
  group('Manual Payroll Entry Tests', () {
    const period = '2026-11';

    setUp(() {
      ManualPayrollService.clearManualRecords(period);
    });

    tearDown(() {
      ManualPayrollService.clearManualRecords(period);
    });

    test('ManualPayrollService saves and loads manual records correctly', () async {
      expect(ManualPayrollService.hasManualRecords(period), false);

      final rec = PayrollRecord(
        epCode: 'EP01',
        nickname: 'Chujai',
        payGroup: 'Date : 1',
        period: period,
        cycleStartDate: DateTime(2026, 10, 2),
        cycleEndDate: DateTime(2026, 11, 1),
        payDate: DateTime(2026, 11, 1),
        baseSalary: 15000.0,
        dailyRate: 500.0,
        isProrate: false,
        workedDays: 26,
        wageType: 'Monthly',
        basePay: 15000.0,
        workDays: 26,
        dayOff: 4,
        housingAllowance: 1000.0,
        overtimePay: 720.0,
        bonusPay: 500.0,
        advanceDeduction: 1500.0,
        workPermitDeduction: 2000.0,
        otherDeduction: 200.0,
        deductionNote: 'หักของแตก',
      );

      // Net Pay = 15,000 + (1,000 + 720 + 500) - (1,500 + 2,000 + 200) = 17,220 - 3,700 = 13,520
      expect(rec.netPay, 13520.0);

      // Save
      final res = await ManualPayrollService.saveManualRecords(
        period: period,
        records: [rec],
      );

      expect(res['savedLocal'], true);
      expect(res['total'], 1);
      expect(ManualPayrollService.hasManualRecords(period), true);

      // Load
      final loaded = ManualPayrollService.loadManualRecords(period);
      expect(loaded, isNotNull);
      expect(loaded!.length, 1);

      final item = loaded.first;
      expect(item['ep_code'], 'EP01');
      expect(item['nickname'], 'Chujai');
      expect(item['base_salary'], 15000.0);
      expect(item['work_days'], 26);
      expect(item['housing_allowance'], 1000.0);
      expect(item['overtime_pay'], 720.0);
      expect(item['bonus_pay'], 500.0);
      expect(item['advance_deduction'], 1500.0);
      expect(item['work_permit_deduction'], 2000.0);
      expect(item['other_deduction'], 200.0);
      expect(item['deduction_note'], 'หักของแตก');
      expect(item['net_pay'], 13520.0);

      // Clear
      ManualPayrollService.clearManualRecords(period);
      expect(ManualPayrollService.hasManualRecords(period), false);
    });

    test('Daily wage manual entry calculates base pay from work days and rate accurately', () {
      final dailyRec = PayrollRecord(
        epCode: 'EP38',
        nickname: 'T.Tar',
        payGroup: 'Date : 1',
        period: period,
        cycleStartDate: DateTime(2026, 10, 2),
        cycleEndDate: DateTime(2026, 11, 1),
        payDate: DateTime(2026, 11, 1),
        baseSalary: 15000.0,
        dailyRate: 500.0,
        isProrate: false,
        workedDays: 25,
        wageType: 'Daily',
        basePay: 500.0 * 25, // 12,500
        workDays: 25,
        dayOff: 5,
        housingAllowance: 1000.0,
      );

      // Net Pay = 12,500 + 1,000 = 13,500
      expect(dailyRec.basePay, 12500.0);
      expect(dailyRec.housingAllowance, 1000.0);
      expect(dailyRec.netPay, 13500.0);
    });

    test('Monthly wage excess day-offs deduction calculates correctly', () {
      final monthlyRec = PayrollRecord(
        epCode: 'EP33',
        nickname: 'Tualek',
        payGroup: 'Date : 1',
        period: period,
        cycleStartDate: DateTime(2026, 10, 2),
        cycleEndDate: DateTime(2026, 11, 1),
        payDate: DateTime(2026, 11, 1),
        baseSalary: 12500.0,
        dailyRate: (12500.0 / 30.0).roundToDouble(), // 417
        isProrate: false,
        workedDays: 25,
        wageType: 'Monthly',
        basePay: 12500.0,
        workDays: 25,
        dayOff: 5,
        sickLeave: 1, // 6 off days -> 2 excess days
        excessDayOffDays: 2.0,
        excessDayOffDeduction: (2.0 * (12500.0 / 30.0)).roundToDouble(), // 833
        housingAllowance: 1000.0,
      );

      // Net Pay = 12,500 + 1,000 - 833 = 12,667
      expect(monthlyRec.excessDayOffDays, 2.0);
      expect(monthlyRec.excessDayOffDeduction, 833.0);
      expect(monthlyRec.netPay, 12667.0);
    });
  });
}
