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
      // Default worked days is 26 for full cycle
      expect(record.workedDays, 26);
      expect(record.basePay, 450 * 26); // 11,700
      expect(record.netPay, 11700);

      // Simulate 20 days worked
      record.workDays = 20;
      record.basePay = (record.dailyRate * record.workDays).roundToDouble();
      expect(record.basePay, 9000);
      expect(record.netPay, 9000);
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
  });
}
