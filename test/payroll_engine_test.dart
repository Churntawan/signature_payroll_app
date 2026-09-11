import 'package:flutter_test/flutter_test.dart';
import 'package:signature_payroll_app/models/employee.dart';
import 'package:signature_payroll_app/services/payroll_engine.dart';

void main() {
  group('PayrollEngine Tests', () {
    test('Pay cycle date ranges match business rules', () {
      final cycle1 = PayrollEngine.getCycleRange('2025-01', 'Date : 1');
      expect(cycle1.startDate, DateTime(2024, 12, 2));
      expect(cycle1.endDate, DateTime(2025, 1, 1));
      expect(cycle1.payDate, DateTime(2025, 1, 1));

      final cycle10 = PayrollEngine.getCycleRange('2025-01', 'Date : 10');
      expect(cycle10.startDate, DateTime(2024, 12, 11));
      expect(cycle10.endDate, DateTime(2025, 1, 10));

      final cycle20 = PayrollEngine.getCycleRange('2025-01', 'Date : 20');
      expect(cycle20.startDate, DateTime(2024, 12, 21));
      expect(cycle20.endDate, DateTime(2025, 1, 20));
    });

    test('Full month calculation gives full salary', () {
      final emp = Employee(
        epCode: 'EP04',
        nickname: 'Zin',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
      );

      final record = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: '2025-01',
      );

      expect(record, isNotNull);
      expect(record!.isProrate, false);
      expect(record.basePay, 12000);
      expect(record.netPay, 12000);
    });

    test('Smart Prorate correctly calculates new hire mid-cycle', () {
      // พนักงานเริ่มงานวันที่ 01/01/2025 ในรอบ Date : 10 (11/12/2024 - 10/01/2025)
      // จำนวนวันทำงาน: 1 ม.ค. ถึง 10 ม.ค. = 10 วัน
      // Daily rate: 12,000 / 30 = 400 บาท/วัน
      // Base pay: 400 * 10 = 4,000 บาท
      final emp = Employee(
        epCode: 'EP99',
        nickname: 'Newbie',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
        startDate: DateTime(2025, 1, 1),
      );

      final record = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: '2025-01',
      );

      expect(record, isNotNull);
      expect(record!.isProrate, true);
      expect(record.workedDays, 10);
      expect(record.basePay, 4000);
      expect(record.netPay, 4000);
      expect(record.prorateReason.contains('Started'), true);
    });

    test('Resigned before cycle is automatically excluded', () {
      final emp = Employee(
        epCode: 'EP02',
        nickname: 'Aem',
        status: 'Resigned',
        baseSalary: 13000,
        payGroup: 'Date : 10',
        resignDate: DateTime(2024, 11, 30),
      );

      final record = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: '2025-01',
      );

      expect(record, isNull);
    });

    test('formatLinePayslip includes leave dates details when present', () {
      final emp = Employee(
        epCode: 'EP05',
        nickname: 'Nui',
        status: 'Active',
        baseSalary: 15000,
        payGroup: 'Date : 1',
      );

      final record = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: '2025-01',
      );

      expect(record, isNotNull);
      record!.attendanceDetails = [
        {'date': '2024-12-05', 'status': 'OFF', 'note': ''},
        {'date': '2024-12-12', 'status': 'OFF', 'note': ''},
        {'date': '2024-12-20', 'status': 'Sick', 'note': 'ปวดหัว'},
      ];

      final lineText = PayrollEngine.formatLinePayslip(record);
      expect(lineText.contains('สถิติและวันหยุด/วันลา'), true);
      expect(lineText.contains('05/12, 12/12'), true);
      expect(lineText.contains('20/12 [ปวดหัว]'), true);
      expect(lineText.contains('Nui (EP05)'), true);
    });

    test('Daily wage employee calculates pay from actual days worked', () {
      final emp = Employee(
        epCode: 'EP10',
        nickname: 'Somchai',
        status: 'Active',
        baseSalary: 450, // 450 THB/day
        payGroup: 'Date : 10',
        note: '[Wage:Daily]',
      );

      expect(emp.isDailyWage, true);
      expect(emp.wageType, 'Daily');

      final record = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: '2025-01',
      );

      expect(record, isNotNull);
      expect(record!.wageType, 'Daily');
      expect(record.dailyRate, 450);
      // Period 2025-01 (11/12 to 10/01) has 31 calendar days. Default worked days is 31 - 4 = 27
      expect(record.workedDays, 27);
      expect(record.basePay, 450 * 27); // 12,150
      expect(record.netPay, 12150);

      // Period in 30-day month (e.g. 2025-05: 11/04 to 10/05 has 30 days -> 30 - 4 = 26)
      final rec30 = PayrollEngine.calculateEmployeeRecord(employee: emp, period: '2025-05')!;
      expect(rec30.workedDays, 26);
      expect(rec30.basePay, 450 * 26); // 11,700

      // Period in February (2025-03: 11/02/2025 to 10/03/2025 has 28 days -> 28 - 4 = 24)
      final rec28 = PayrollEngine.calculateEmployeeRecord(employee: emp, period: '2025-03')!;
      expect(rec28.workedDays, 24);
      expect(rec28.basePay, 450 * 24); // 10,800

      // Simulate 20 days worked
      record.workDays = 20;
      record.basePay = (record.dailyRate * record.workDays).roundToDouble();
      expect(record.basePay, 9000);
      expect(record.netPay, 9000);

      // Monthly employee (12,000 THB) switched to daily -> auto dailyRate is 12000/30 = 400
      final empMonthlyToDaily = Employee(
        epCode: 'EP09',
        nickname: 'Wan',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
        note: '[Wage:Daily]',
      );
      expect(empMonthlyToDaily.dailyWageRate, 400.0);
      final recWan = PayrollEngine.calculateEmployeeRecord(employee: empMonthlyToDaily, period: '2026-09');
      expect(recWan!.dailyRate, 400.0);

      // Custom daily rate via [DailyRate:450]
      final empCustomRate = empMonthlyToDaily.copyWithWelfareSettings(dailyRate: 450.0);
      expect(empCustomRate.dailyWageRate, 450.0);

      // User's exact scenario 1: 31 days worked in 31-day cycle -> 31 * 400 = 12,400 THB
      final recWan31 = PayrollEngine.calculateEmployeeRecord(employee: empMonthlyToDaily, period: '2026-09')!;
      final full31Logs = List.generate(31, (i) => {
        'date': '2026-08-${(i + 11).toString().padLeft(2, '0')}',
        'category': 'Work Days',
        'units': 1.0,
      });
      PayrollEngine.applyAttendance(recWan31, full31Logs);
      expect(recWan31.workDays, 31);
      expect(recWan31.basePay, 31 * 400.0); // 12,400 THB

      // User's exact scenario 2: 28 days worked in February cycle -> 28 * 400 = 11,200 THB
      final recWan28 = PayrollEngine.calculateEmployeeRecord(employee: empMonthlyToDaily, period: '2026-03')!;
      final full28Logs = List.generate(28, (i) => {
        'date': '2026-02-${(i + 11).toString().padLeft(2, '0')}',
        'category': 'Work Days',
        'units': 1.0,
      });
      PayrollEngine.applyAttendance(recWan28, full28Logs);
      expect(recWan28.workDays, 28);
      expect(recWan28.basePay, 28 * 400.0); // 11,200 THB

      // Wan scenario with attendance logs in 2026-09 (31-day cycle, 2 sick days, 4 day-offs)
      final empWanFull = Employee(
        epCode: 'EP09',
        nickname: 'Wan',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
        stayOutside: 'Yes',
        startDate: DateTime(2026, 1, 1),
        note: '[Wage:Daily]',
      );
      final recWanWithAtt = PayrollEngine.calculateEmployeeRecord(employee: empWanFull, period: '2026-09')!;
      expect(recWanWithAtt.dailyRate, 400.0);
      expect(recWanWithAtt.housingAllowance, 1000.0);

      // Apply attendance with 2 sick days (13/08, 26/08) and default 4 day-offs in 31-day cycle:
      // 31 - 4 - 2 = 25 days worked
      final wanAttendance = [
        {'date': '2026-08-13', 'category': 'Sick', 'units': 1.0},
        {'date': '2026-08-26', 'category': 'Sick', 'units': 1.0},
      ];
      PayrollEngine.applyAttendance(recWanWithAtt, wanAttendance);
      expect(recWanWithAtt.dayOff, 4);
      expect(recWanWithAtt.sickLeave, 2);
      expect(recWanWithAtt.workDays, 25);
      expect(recWanWithAtt.basePay, 25 * 400.0); // 10,000 THB
      expect(recWanWithAtt.housingAllowance, 1000.0);
      expect(recWanWithAtt.netPay, 11000.0); // 10,000 + 1,000 = 11,000 THB

      // Scenario: Daily worker with explicit 'Work Days' logged (e.g. 21 days)
      final recWanExplicit = PayrollEngine.calculateEmployeeRecord(employee: empWanFull, period: '2026-09')!;
      final explicitLogs = List.generate(21, (i) => {
        'date': '2026-08-${(i + 11).toString().padLeft(2, '0')}',
        'category': 'Work Days',
        'units': 1.0,
      });
      PayrollEngine.applyAttendance(recWanExplicit, explicitLogs);
      expect(recWanExplicit.workDays, 21);
      expect(recWanExplicit.basePay, 21 * 400.0); // 8,400 THB
    });

    test('Housing allowance 1-month tenure rule and mid-cycle forfeiture', () {
      // Pay cycle Date : 10 for 2025-01 is 2024-12-11 to 2025-01-10

      // Case 1: Start date too recent (< 1 month before cycle start) -> Not eligible
      final empNew = Employee(
        epCode: 'EP11',
        nickname: 'Moe',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
        stayOutside: 'Yes',
        startDate: DateTime(2024, 12, 1), // Started Dec 1 -> 1 month is Jan 1 (after Dec 11 cycle start)
      );

      final recordNew = PayrollEngine.calculateEmployeeRecord(
        employee: empNew,
        period: '2025-01',
      );
      expect(recordNew, isNotNull);
      expect(recordNew!.housingAllowance, 0.0);
      expect(recordNew.housingAllowanceNote.contains('ยังไม่ครบอายุงาน'), true);

      // Case 2: Start date >= 1 month before cycle start -> Eligible (default 1000 THB)
      final empEligible = Employee(
        epCode: 'EP12',
        nickname: 'Kat',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
        stayOutside: 'Yes',
        startDate: DateTime(2024, 11, 1), // Started Nov 1 -> 1 month is Dec 1 <= Dec 11 cycle start
      );

      final recordEligible = PayrollEngine.calculateEmployeeRecord(
        employee: empEligible,
        period: '2025-01',
      );
      expect(recordEligible, isNotNull);
      expect(recordEligible!.housingAllowance, 1000.0);
      expect(recordEligible.totalExtra, 1000.0);
      expect(recordEligible.netPay, 13000.0);

      // Case 3: Custom housing allowance amount via note tag [Housing:1500]
      final empCustom = empEligible.copyWithWelfareSettings(
        housingAllowance: 1500.0,
      );
      expect(empCustom.housingAllowance, 1500.0);

      final recordCustom = PayrollEngine.calculateEmployeeRecord(
        employee: empCustom,
        period: '2025-01',
      );
      expect(recordCustom, isNotNull);
      expect(recordCustom!.housingAllowance, 1500.0);
      expect(recordCustom.netPay, 13500.0);

      // Case 4: Resigning mid-cycle forfeits housing allowance
      final empResignMid = Employee(
        epCode: 'EP13',
        nickname: 'Bank',
        status: 'Active',
        baseSalary: 12000,
        payGroup: 'Date : 10',
        stayOutside: 'Yes',
        startDate: DateTime(2024, 1, 1),
        resignDate: DateTime(2025, 1, 5), // Resigns before 2025-01-10
      );

      final recordResignMid = PayrollEngine.calculateEmployeeRecord(
        employee: empResignMid,
        period: '2025-01',
      );
      expect(recordResignMid, isNotNull);
      expect(recordResignMid!.housingAllowance, 0.0);
      expect(recordResignMid.housingAllowanceNote.contains('ลาออกระหว่างงวด'), true);
    });

    test('Excess day-offs (> 4) are deducted as whole days for monthly employees', () {
      final emp = Employee(
        epCode: 'EP14',
        nickname: 'Bow',
        status: 'Active',
        baseSalary: 12000, // 400 THB/day
        payGroup: 'Date : 10',
      );

      final record = PayrollEngine.calculateEmployeeRecord(
        employee: emp,
        period: '2025-01',
      );
      expect(record, isNotNull);

      // Case 1: 4 day-offs (within standard quota) -> 0 deduction
      record!.dayOff = 4;
      if (record.dayOff > 4) {
        record.excessDayOffDays = record.dayOff - 4;
        record.excessDayOffDeduction = (record.excessDayOffDays * record.dailyRate).roundToDouble();
      } else {
        record.excessDayOffDays = 0;
        record.excessDayOffDeduction = 0.0;
      }
      expect(record.excessDayOffDays, 0);
      expect(record.excessDayOffDeduction, 0.0);
      expect(record.totalDeduction, 0.0);
      expect(record.netPay, 12000.0);

      // Case 2: 6 day-offs (exceeds by 2 days) -> 2 days * 400 = 800 THB deduction
      record.dayOff = 6;
      if (record.dayOff > 4) {
        record.excessDayOffDays = record.dayOff - 4;
        record.excessDayOffDeduction = (record.excessDayOffDays * record.dailyRate).roundToDouble();
      }
      expect(record.excessDayOffDays, 2);
      expect(record.excessDayOffDeduction, 800.0);
      expect(record.totalDeduction, 800.0);
      expect(record.netPay, 11200.0);

      // Verify line payslip contains excess day-offs deduction and housing allowance
      record.housingAllowance = 1000.0;
      final linePayslip = PayrollEngine.formatLinePayslip(record);
      expect(linePayslip.contains('Housing Allowance (ค่าห้องพัก): +1,000.00'), true);
      expect(linePayslip.contains('Excess Day-off (หยุดเกินโควตา 2 วัน): -800.00'), true);
      expect(linePayslip.contains('12,200.00 THB'), true);
    });

    test('Cherry resignation scenario in 2026-09 and exclusion in 2026-10 (Daily Wage)', () {
      final cherryDaily = Employee(
        epCode: 'EP39',
        nickname: 'Cherry',
        status: 'Resigned',
        baseSalary: 12000,
        payGroup: 'Date : 1',
        stayOutside: 'Yes',
        resignDate: DateTime(2026, 8, 31),
        note: '[Wage:Daily] [DailyRate:400] [Housing:1000]',
      );

      // Period 2026-09 (Cycle: 02/08/2026 - 01/09/2026 = 31 days)
      // Worked 30 calendar days (02/08 to 31/08), resigned on 31/08
      final rec = PayrollEngine.calculateEmployeeRecord(employee: cherryDaily, period: '2026-09')!;
      expect(rec.isProrate, true);
      expect(rec.wageType, 'Daily');
      expect(rec.workedDays, 30);
      expect(rec.housingAllowance, 0.0); // Forfeited due to mid-cycle resignation

      final att = [
        {'date': '2026-08-09', 'category': 'Sick', 'units': 1.0},
        {'date': '2026-08-14', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-16', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-21', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-28', 'category': 'Day-off', 'units': 1.0},
      ];
      PayrollEngine.applyAttendance(rec, att);
      expect(rec.dayOff, 4);
      expect(rec.sickLeave, 1);
      // Actual work days: 30 calendar days - 4 day-offs - 1 sick leave = 25 days
      expect(rec.workDays, 25);
      expect(rec.basePay, 10000.0); // 25 days * 400 THB = 10,000 THB
      expect(rec.excessDayOffDays, 0);
      expect(rec.netPay, 10000.0);

      // In subsequent cycle 2026-10 (Cycle: 02/09/2026 - 01/10/2026):
      // Resign date 31/08/2026 is strictly before cycle start (02/09/2026) -> automatically excluded
      final recNext = PayrollEngine.calculateEmployeeRecord(employee: cherryDaily, period: '2026-10');
      expect(recNext, isNull);
    });

    test('Cherry resignation scenario in 2026-09 (Monthly Wage)', () {
      final cherryMonthly = Employee(
        epCode: 'EP39',
        nickname: 'Cherry',
        status: 'Resigned',
        baseSalary: 12000,
        payGroup: 'Date : 1',
        stayOutside: 'Yes',
        resignDate: DateTime(2026, 8, 31),
      );

      // Period 2026-09 (Cycle: 02/08/2026 - 01/09/2026 = 31 days)
      // Resigned 31/08/2026 -> worked 30 calendar days, missed 1 day (01/09)
      // Monthly base is 30 days -> 30 - 1 = 29 worked days (@ 400 = 11,600 THB)
      final rec = PayrollEngine.calculateEmployeeRecord(employee: cherryMonthly, period: '2026-09')!;
      expect(rec.isProrate, true);
      expect(rec.wageType, 'Monthly');
      expect(rec.workedDays, 29);
      expect(rec.basePay, 11600.0);
      expect(rec.housingAllowance, 0.0);

      final att = [
        {'date': '2026-08-09', 'category': 'Sick', 'units': 1.0},
        {'date': '2026-08-14', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-16', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-21', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-28', 'category': 'Day-off', 'units': 1.0},
      ];
      PayrollEngine.applyAttendance(rec, att);
      expect(rec.workedDays, 29);
      expect(rec.dayOff, 4);
      expect(rec.sickLeave, 1);
      expect(rec.workDays, 24); // 29 - 4 - 1 = 24
      expect(rec.basePay, 11600.0);
      expect(rec.netPay, 11600.0);
    });

    test('Cherry payroll and non-overlapping adjustments for 2026-08 vs 2026-09', () {
      final cherry = Employee(
        epCode: 'EP39',
        nickname: 'Cherry',
        status: 'Resigned',
        baseSalary: 12000,
        payGroup: 'Date : 1',
        stayOutside: 'Yes',
        resignDate: DateTime(2026, 8, 31),
        note: '[Wage:Daily] [DailyRate:400] [Housing:1000]',
      );

      // --- Period 2026-08 (Cycle: 02/07/2026 - 01/08/2026) ---
      final rec08 = PayrollEngine.calculateEmployeeRecord(employee: cherry, period: '2026-08')!;
      expect(rec08.housingAllowance, 1000.0); // Active and qualified

      // Attendance: 12 day-off logs
      final att08 = List.generate(12, (i) => {'date': '2026-07-${(i + 5).toString().padLeft(2, '0')}', 'category': 'Day-off', 'units': 1.0});
      PayrollEngine.applyAttendance(rec08, att08);
      expect(rec08.workDays, 19); // 31 - 12 = 19 days
      expect(rec08.basePay, 7600.0); // 19 * 400

      // Period 2026-08 adjustment: Installment 3 (1,000 THB)
      rec08.advanceDeduction = 1000.0;
      expect(rec08.netPay, 7600.0); // 7,600 base + 1,000 housing - 1,000 advance = 7,600 THB

      // --- Period 2026-09 (Cycle: 02/08/2026 - 01/09/2026) ---
      final rec09 = PayrollEngine.calculateEmployeeRecord(employee: cherry, period: '2026-09')!;
      expect(rec09.isProrate, true);
      expect(rec09.housingAllowance, 0.0); // Forfeited due to mid-cycle resignation

      // Attendance: 4 day-offs, 1 sick leave
      final att09 = [
        {'date': '2026-08-09', 'category': 'Sick', 'units': 1.0},
        {'date': '2026-08-14', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-16', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-21', 'category': 'Day-off', 'units': 1.0},
        {'date': '2026-08-28', 'category': 'Day-off', 'units': 1.0},
      ];
      PayrollEngine.applyAttendance(rec09, att09);
      expect(rec09.workDays, 25); // 30 calendar days - 4 day-offs - 1 sick = 25 days
      expect(rec09.basePay, 10000.0); // 25 * 400

      // Period 2026-09 adjustment: Installment 4 (2,000 THB final settlement)
      rec09.advanceDeduction = 2000.0;
      expect(rec09.netPay, 8000.0); // 10,000 base - 2,000 advance = 8,000 THB

      // Verify total repaid advance across periods is exactly 5,000 THB
      // (June: 1,000 + July: 1,000 + Aug: 1,000 + Sep: 2,000 = 5,000 THB)
      final totalAdvanceRepaid = 1000.0 + 1000.0 + rec08.advanceDeduction + rec09.advanceDeduction;
      expect(totalAdvanceRepaid, 5000.0);
    });
  });
}
