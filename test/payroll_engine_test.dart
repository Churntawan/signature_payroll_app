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
  });
}
