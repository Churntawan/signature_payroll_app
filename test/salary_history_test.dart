import 'package:flutter_test/flutter_test.dart';
import 'package:signature_payroll_app/models/employee.dart';
import 'package:signature_payroll_app/models/salary_record.dart';
import 'package:signature_payroll_app/services/payroll_engine.dart';
import 'package:signature_payroll_app/services/salary_history_service.dart';

void main() {
  group('Salary History & Effective Period Tests', () {
    setUp(() {
      SalaryHistoryService.resetForTesting([]);
    });

    test('SalaryRecord model serializes and deserializes correctly', () {
      final now = DateTime(2026, 9, 11, 14, 30);
      final rec = SalaryRecord(
        id: 'sal_EP01_2026-10_123456',
        epCode: 'EP01',
        effectivePeriod: '2026-10',
        baseSalary: 15000.0,
        previousSalary: 12000.0,
        reason: 'ผ่านโปรทดลองงาน',
        createdAt: now,
        createdByName: 'Admin Churn',
      );

      expect(rec.salaryDiff, equals(3000.0));

      final json = rec.toJson();
      expect(json['id'], equals('sal_EP01_2026-10_123456'));
      expect(json['ep_code'], equals('EP01'));
      expect(json['effective_period'], equals('2026-10'));
      expect(json['base_salary'], equals(15000.0));
      expect(json['previous_salary'], equals(12000.0));
      expect(json['reason'], equals('ผ่านโปรทดลองงาน'));
      expect(json['created_by'], equals('Admin Churn'));

      final fromJson = SalaryRecord.fromJson(json);
      expect(fromJson.id, equals(rec.id));
      expect(fromJson.epCode, equals(rec.epCode));
      expect(fromJson.effectivePeriod, equals(rec.effectivePeriod));
      expect(fromJson.baseSalary, equals(rec.baseSalary));
      expect(fromJson.previousSalary, equals(rec.previousSalary));
      expect(fromJson.reason, equals(rec.reason));
      expect(fromJson.salaryDiff, equals(3000.0));
    });

    test('getSalaryForPeriod returns defaultSalary when no history exists', () {
      final salary = SalaryHistoryService.getSalaryForPeriod(
        epCode: 'EP01',
        period: '2026-09',
        defaultSalary: 12000.0,
      );
      expect(salary, equals(12000.0));
    });

    test('getSalaryForPeriod correctly protects historical periods from future adjustments', () async {
      // Employee has baseSalary 12,000
      // In 2026-10, salary is adjusted to 15,000 (reason: promotion)
      final record = SalaryRecord(
        id: 'sal_1',
        epCode: 'EP01',
        effectivePeriod: '2026-10',
        baseSalary: 15000.0,
        previousSalary: 12000.0,
        reason: 'ปรับเงินเดือนประจำปี',
        createdAt: DateTime.now(),
      );

      await SalaryHistoryService.addSalaryRecord(record);

      expect(SalaryHistoryService.hasHistory('EP01'), isTrue);
      expect(SalaryHistoryService.hasHistory('EP02'), isFalse);

      // Period 2026-08 (Past period): Must still be 12,000!
      final pastSalaryAug = SalaryHistoryService.getSalaryForPeriod(
        epCode: 'EP01',
        period: '2026-08',
        defaultSalary: 12000.0,
      );
      expect(pastSalaryAug, equals(12000.0));

      // Period 2026-09 (Current period before effective date): Must still be 12,000!
      final pastSalarySep = SalaryHistoryService.getSalaryForPeriod(
        epCode: 'EP01',
        period: '2026-09',
        defaultSalary: 12000.0,
      );
      expect(pastSalarySep, equals(12000.0));

      // Period 2026-10 (Effective period): Must be 15,000!
      final effectiveSalaryOct = SalaryHistoryService.getSalaryForPeriod(
        epCode: 'EP01',
        period: '2026-10',
        defaultSalary: 12000.0,
      );
      expect(effectiveSalaryOct, equals(15000.0));

      // Period 2026-11 (Future period): Must stay 15,000!
      final futureSalaryNov = SalaryHistoryService.getSalaryForPeriod(
        epCode: 'EP01',
        period: '2026-11',
        defaultSalary: 12000.0,
      );
      expect(futureSalaryNov, equals(15000.0));
    });

    test('getSalaryForPeriod handles multiple adjustments across timeline', () async {
      // Timeline:
      // Starting salary: 10,000
      // 2025-06: 12,000 (probation passed)
      // 2026-01: 14,000 (annual increment)
      // 2026-10: 16,000 (promotion to supervisor)
      final records = [
        SalaryRecord(
          id: 'sal_1',
          epCode: 'EP05',
          effectivePeriod: '2025-06',
          baseSalary: 12000.0,
          previousSalary: 10000.0,
          reason: 'ผ่านโปร',
          createdAt: DateTime.now(),
        ),
        SalaryRecord(
          id: 'sal_2',
          epCode: 'EP05',
          effectivePeriod: '2026-01',
          baseSalary: 14000.0,
          previousSalary: 12000.0,
          reason: 'ปรับประจำปี',
          createdAt: DateTime.now(),
        ),
        SalaryRecord(
          id: 'sal_3',
          epCode: 'EP05',
          effectivePeriod: '2026-10',
          baseSalary: 16000.0,
          previousSalary: 14000.0,
          reason: 'เลื่อนตำแหน่งหัวหน้างาน',
          createdAt: DateTime.now(),
        ),
      ];

      for (final r in records) {
        await SalaryHistoryService.addSalaryRecord(r);
      }

      // Check chronological retrieval
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2025-01', defaultSalary: 10000.0), equals(10000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2025-05', defaultSalary: 10000.0), equals(10000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2025-06', defaultSalary: 10000.0), equals(12000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2025-12', defaultSalary: 10000.0), equals(12000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2026-01', defaultSalary: 10000.0), equals(14000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2026-09', defaultSalary: 10000.0), equals(14000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2026-10', defaultSalary: 10000.0), equals(16000.0));
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP05', period: '2026-12', defaultSalary: 10000.0), equals(16000.0));
    });

    test('deleteSalaryRecord successfully removes mistaken entry and reverts salary', () async {
      final record = SalaryRecord(
        id: 'erroneous_record',
        epCode: 'EP01',
        effectivePeriod: '2026-10',
        baseSalary: 20000.0, // Mistaken salary entry
        previousSalary: 12000.0,
        reason: 'คีย์ผิด',
        createdAt: DateTime.now(),
      );

      await SalaryHistoryService.addSalaryRecord(record);
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP01', period: '2026-10', defaultSalary: 12000.0), equals(20000.0));

      // User deletes the wrong record to correct history
      final deleted = await SalaryHistoryService.deleteSalaryRecord('erroneous_record');
      expect(deleted, isTrue);

      // Now 2026-10 reverts back to 12,000.0
      expect(SalaryHistoryService.getSalaryForPeriod(epCode: 'EP01', period: '2026-10', defaultSalary: 12000.0), equals(12000.0));
    });

    test('PayrollEngine seamlessly integrates with period-effective salary', () async {
      final employee = Employee(
        epCode: 'EP01',
        nickname: 'Chujai',
        status: 'Active',
        baseSalary: 12000.0,
        payGroup: 'Date : 10',
      );

      // Add salary adjustment for 2026-10: 15,000
      await SalaryHistoryService.addSalaryRecord(
        SalaryRecord(
          id: 'sal_ep01',
          epCode: 'EP01',
          effectivePeriod: '2026-10',
          baseSalary: 15000.0,
          previousSalary: 12000.0,
          reason: 'ปรับเงินเดือนงวด 10',
          createdAt: DateTime.now(),
        ),
      );

      // 1. Calculate for 2026-09: baseSalary must be 12,000 and basePay 12,000
      final recSep = PayrollEngine.calculateEmployeeRecord(employee: employee, period: '2026-09');
      expect(recSep, isNotNull);
      expect(recSep!.baseSalary, equals(12000.0));
      expect(recSep.basePay, equals(12000.0));
      expect(recSep.dailyRate, equals(400.0));

      // 2. Calculate for 2026-10: baseSalary must be 15,000 and basePay 15,000
      final recOct = PayrollEngine.calculateEmployeeRecord(employee: employee, period: '2026-10');
      expect(recOct, isNotNull);
      expect(recOct!.baseSalary, equals(15000.0));
      expect(recOct.basePay, equals(15000.0));
      expect(recOct.dailyRate, equals(500.0));
    });
  });
}
