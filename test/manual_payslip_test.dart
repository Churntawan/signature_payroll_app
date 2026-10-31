import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signature_payroll_app/models/employee.dart';
import 'package:signature_payroll_app/models/payroll_record.dart';
import 'package:signature_payroll_app/widgets/manual_payslip_creator.dart';

void main() {
  group('Manual PaySlip Creator Tests', () {
    testWidgets('ManualPayslipCreator renders and calculates net pay in real-time', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      PayrollRecord? savedRecord;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualPayslipCreator(
              period: '2026-10',
              employees: [
                Employee(
                  epCode: 'EP01',
                  nickname: 'ชูใจ',
                  status: 'Active',
                  baseSalary: 15000.0,
                  payGroup: 'Date : 1',
                  stayOutside: 'Yes',
                ),
              ],
              onSaveToRecords: (rec) {
                savedRecord = rec;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and form components
      expect(find.text('SIGNATURE PAYROLL'), findsOneWidget);
      expect(find.text('PAYSLIP / SALARY STATEMENT'), findsOneWidget);
      expect(find.text('NET PAYOUT'), findsOneWidget);
      expect(find.text('💰 1. ตัวเลข & ยอดเงิน'), findsOneWidget);
      expect(find.text('✏️ 2. ปรับแต่งข้อความบนสลิป'), findsOneWidget);

      // Verify buttons exist
      expect(find.text('คัดลอกส่ง LINE'), findsOneWidget);
      expect(find.text('📸 เซฟเป็นรูปภาพ (PNG)'), findsOneWidget);
      expect(find.text('💾 บันทึกเข้าระบบ'), findsOneWidget);

      // Tap tab 2 to edit text
      await tester.tap(find.text('✏️ 2. ปรับแต่งข้อความบนสลิป'));
      await tester.pumpAndSettle();

      expect(find.text('1. ส่วนหัวสลิป (Header)'), findsOneWidget);
      expect(find.text('รีเซ็ตข้อความ'), findsOneWidget);

      // Tap Save button
      await tester.tap(find.text('💾 บันทึกเข้าระบบ'));
      await tester.pumpAndSettle();

      expect(savedRecord, isNotNull);
      expect(savedRecord!.epCode, isNotEmpty);
      expect(savedRecord!.netPay, greaterThan(0));
    });
  });
}
