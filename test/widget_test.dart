// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signature_payroll_app/main.dart';

void main() {
  testWidgets('SignaturePayrollApp smoke test: shows login screen and logs in as admin', (WidgetTester tester) async {
    await tester.pumpWidget(const SignaturePayrollApp());
    await tester.pumpAndSettle();

    // Login screen shows brand and login button
    expect(find.text('SIGNATURE'), findsWidgets);
    expect(find.text('PAYROLL SUITE'), findsWidgets);
    expect(find.text('เข้าสู่ระบบจัดการ (Admin)'), findsOneWidget);

    // Enter admin password
    await tester.enterText(find.byType(TextField).first, 'Churn2543');
    await tester.tap(find.text('เข้าสู่ระบบจัดการ (Admin)'));
    await tester.pumpAndSettle();

    // After login, admin dashboard appears
    expect(find.text('SIGNATURE PAYROLL'), findsWidgets);
  });
}
