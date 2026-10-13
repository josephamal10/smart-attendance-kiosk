import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:technerdz_app/models/employee.dart';
import 'package:technerdz_app/screens/admin_login_screen.dart';
import 'package:technerdz_app/screens/kiosk_screen.dart';

void main() {
  testWidgets('Kiosk opens on check-in instructions with a small admin entry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: KioskScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('HOW TO CHECK IN'), findsOneWidget);
    expect(find.text('Blink once'), findsOneWidget);
    expect(find.byTooltip('Admin sign-in'), findsOneWidget);
    // No real camera in tests: the stage shows a status instead of crashing
    expect(find.textContaining('amera'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Admin sign-in asks for username and password', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));
    expect(find.text('Admin sign-in'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Enter your username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Enter your password'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  test('Employee parses category and tolerates missing fields', () {
    final e = Employee.fromJson({'id': 2, 'name': 'Joseph Amal', 'category': 'Developer'});
    expect(e.category, 'Developer');
    expect(e.role, 'user');
    expect(e.isActive, isTrue);
    expect(Employee.fromJson({'id': 3, 'name': 'New'}).category, isNull);
  });

  test('AttendanceLog parses null out_time', () {
    final log = AttendanceLog.fromJson({
      'id': 1, 'employee_id': 2, 'date': '2026-10-12',
      'in_time': '2026-10-12T09:01:00', 'out_time': null, 'status': 'present',
    });
    expect(log.inTime!.hour, 9);
    expect(log.outTime, isNull);
  });
}
