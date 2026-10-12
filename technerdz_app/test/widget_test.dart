import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:technerdz_app/models/employee.dart';
import 'package:technerdz_app/screens/lock_screen.dart';

void main() {
  testWidgets('Lock screen shows brand and hint', (tester) async {
    // Plain MaterialApp (not AppTheme) so the test doesn't download Google Fonts
    await tester.pumpWidget(const MaterialApp(home: LockScreen()));
    await tester.pump(const Duration(seconds: 2)); // let the fade-in finish

    expect(find.text('TECHNERDZ'), findsOneWidget);
    expect(find.text('CLICK OR PRESS ANY KEY TO CONTINUE'), findsOneWidget);
  });

  test('Employee parses the public login list (no role / is_active)', () {
    final e = Employee.fromJson({'id': 2, 'name': 'Joseph Amal', 'username': 'Amal'});
    expect(e.role, 'user');
    expect(e.isActive, isTrue);
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
