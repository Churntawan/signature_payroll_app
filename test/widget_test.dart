// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signature_payroll_app/main.dart';
import 'package:signature_payroll_app/services/auth_service.dart';
import 'package:signature_payroll_app/widgets/manual_payroll_sheet.dart';
import 'package:signature_payroll_app/widgets/manual_payslip_creator.dart';

void main() {
  setUp(() {
    AuthService.clearSession();
  });

  testWidgets('SignaturePayrollApp smoke test: shows login screen and logs in as admin', (WidgetTester tester) async {
    await tester.pumpWidget(const SignaturePayrollApp());
    await tester.pumpAndSettle();

    // Login screen shows brand and login button
    expect(find.text('SIGNATURE'), findsWidgets);
    expect(find.byType(ElevatedButton), findsOneWidget);

    // Enter admin password
    await tester.enterText(find.byType(TextField).first, 'Churn2543');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // After login, admin dashboard appears
    expect(find.text('SIGNATURE PAYROLL'), findsWidgets);
  });

  testWidgets('SignaturePayrollApp can toggle to Manual Sheet mode', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SignaturePayrollApp());
    await tester.pumpAndSettle();

    // Login if needed
    final tf = find.byType(TextField);
    if (tf.evaluate().isNotEmpty) {
      await tester.enterText(tf.first, 'Churn2543');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }

    // Check mode switcher exists
    expect(find.text('📊 คำนวณอัตโนมัติ (Cards)'), findsOneWidget);
    expect(find.text('📝 ตารางคีย์แมนนวล (Manual Sheet)'), findsOneWidget);

    // Tap to switch to Manual Sheet mode
    await tester.tap(find.text('📝 ตารางคีย์แมนนวล (Manual Sheet)'));
    await tester.pumpAndSettle();

    // ManualPayrollSheet widget is present!
    expect(find.byType(ManualPayrollSheet), findsOneWidget);
    expect(find.text('💾 บันทึกทั้งหมด'), findsOneWidget);
    expect(find.text('ดึงค่าคำนวณอัตโนมัติ'), findsOneWidget);
    expect(find.text('เพิ่มแถวพนักงาน'), findsOneWidget);
  });

  testWidgets('SignaturePayrollApp Payslip tab can toggle to Manual Creator mode', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SignaturePayrollApp());
    await tester.pumpAndSettle();

    // Login if needed
    final tf = find.byType(TextField);
    if (tf.evaluate().isNotEmpty) {
      await tester.enterText(tf.first, 'Churn2543');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }

    // Navigate to Payslip tab (Tab index 3)
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    // Check mode switcher in Payslip tab
    expect(find.text('📄 สลิปตามระบบ (Standard)'), findsOneWidget);
    expect(find.text('✍️ ออกสลิปแมนนวล (Manual Creator)'), findsOneWidget);

    // Tap to switch to Manual PaySlip Creator
    await tester.tap(find.text('✍️ ออกสลิปแมนนวล (Manual Creator)'));
    await tester.pumpAndSettle();

    // ManualPayslipCreator is visible
    expect(find.byType(ManualPayslipCreator), findsOneWidget);
    expect(find.text('✍️ ระบบออกสลิปเงินเดือนแบบแมนนวล (Manual PaySlip Creator)'), findsOneWidget);
    expect(find.text('📸 เซฟเป็นรูปภาพ (PNG)'), findsOneWidget);
    expect(find.text('คัดลอกส่ง LINE'), findsOneWidget);
  });
}
