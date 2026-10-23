import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:technerdz_app/models/employee.dart';
import 'package:technerdz_app/screens/admin_login_screen.dart';
import 'package:technerdz_app/screens/kiosk_screen.dart';
import 'package:technerdz_app/screens/lock_screen.dart';
import 'package:technerdz_app/screens/my_attendance_screen.dart';
import 'package:technerdz_app/services/api_service.dart';
import 'package:technerdz_app/widgets/ui.dart';

void main() {
  testWidgets('Lock screen shows the clock, the company and both corner icons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: LockScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tap anywhere to check in or out'), findsOneWidget);
    expect(find.text('NANONINO'), findsOneWidget);
    expect(find.byTooltip('Admin sign-in'), findsOneWidget);
    expect(find.textContaining('My dashboard'), findsOneWidget);
    expect(find.text('HOW TO CHECK IN'), findsNothing); // camera not open yet
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Lock screen warns when the server cannot be reached', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: LockScreen()));
    // Tests have no server: every request fails, so the badge appears after the first check
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.textContaining('Offline'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Tapping anywhere on the lock screen opens the camera, Back returns', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: LockScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(300, 500));
    await tester.pump(); // first frame of the page transition
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('HOW TO CHECK IN'), findsOneWidget);
    expect(find.text('Blink once'), findsOneWidget);
    // No real camera in tests: the stage shows a status instead of crashing
    expect(find.textContaining('amera'), findsWidgets);

    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tap anywhere to check in or out'), findsOneWidget);
    expect(find.text('HOW TO CHECK IN'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('The My dashboard icon opens the camera in identify-only mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: LockScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('My dashboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('HOW TO OPEN YOUR DASHBOARD'), findsOneWidget);
    expect(find.textContaining('will not check you in'), findsOneWidget);
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

  test('Durations read like "8h 05m"', () {
    expect(formatMinutes(485), '8h 05m');
    expect(formatMinutes(59), '0h 59m');
  });

  testWidgets('Flags become readable badges', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FlagBadges(
        flags: ['late', 'half_day', 'missed_checkout'], lateMinutes: 16))));
    expect(find.text('Late 16m'), findsOneWidget);
    expect(find.text('Half day'), findsOneWidget);
    expect(find.text('Missed check-out'), findsOneWidget);
  });

  testWidgets('No flags shows the "clean" badge when given', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FlagBadges(
        flags: [], whenClean: StatusBadge('On time', tone: Tone.success)))));
    expect(find.text('On time'), findsOneWidget);
  });

  testWidgets("Kiosk result card shows greeting, status and today's summary", (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    await tester.pumpWidget(const MaterialApp(home: KioskScreen(demoResult: {
      'recognized': true, 'name': 'Priya Raman', 'category': 'HR', 'action': 'in',
      'time': '2026-10-15T09:27:00', 'greeting': 'Good morning, Priya!',
      'flags': ['late'], 'late_minutes': 12, 'message': 'Have a great day!', 'self_token': 't',
    })));
    await tester.pump();
    expect(find.text('Good morning, Priya!'), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Late by 12 min'), findsOneWidget);
    expect(find.text('My dashboard'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('My dashboard shows calendar, hours, leave balance, badges, notices and team', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 1400));
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final days = DateUtils.getDaysInMonth(now.year, now.month);
    String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
    final data = {
      'month': {'present': 9, 'late': 1, 'leave': 1, 'absent': 0, 'working_days': 11, 'avg_hours': 8.9,
          'overtime_hours': 2.5},
      'calendar': {
        'year': now.year, 'month': now.month, 'month_name': 'This month',
        'days': [for (var i = 0; i < days; i++)
          {'date': ymd(first.add(Duration(days: i))), 'day': i + 1, 'weekday': 'Mon', 'working': true, 'holiday': null}],
        'row': {'cells': [for (var i = 0; i < days; i++)
          i == 0 ? {'status': 'late', 'in': '09:40', 'out': '18:00', 'flags': ['late'], 'worked_minutes': 500,
              'overtime_minutes': 0} : {'status': 'future'}]},
      },
      'weekly_hours': [for (var i = 0; i < 8; i++) {'week_start': '2026-01-01', 'label': 'W$i', 'hours': 40.0 + i, 'expected': 45.0}],
      'streak': {'current': 6, 'best': 12},
      'badges': [
        {'key': 'on_a_roll', 'title': 'On a roll', 'description': '5 in a row', 'earned': true, 'progress': '5/5'},
        {'key': 'perfect_week', 'title': 'Perfect week', 'description': 'All on time', 'earned': false, 'progress': null},
      ],
      'leave_balance': [{'kind': 'casual', 'label': 'Casual', 'allowance': 12, 'used': 4, 'pending': 1, 'remaining': 8}],
      'updates': [{'type': 'leave', 'title': 'Casual leave, 20 Oct', 'status': 'approved', 'at': now.toIso8601String()}],
      'notices': [{'id': 1, 'title': 'Fire drill Friday', 'body': 'At 11 AM', 'pinned': true, 'expires_on': null,
          'created_at': now.toIso8601String(), 'created_by': 'Boss'}],
      'team': {'name': 'Tester', 'shift': '09:00–18:00', 'members': 4, 'on_leave_today': ['Mira'],
          'upcoming_holidays': [{'date': ymd(now.add(const Duration(days: 3))), 'name': 'Founders day', 'in_days': 3}]},
    };
    await tester.pumpWidget(MaterialApp(home: MyAttendanceScreen(token: 't', name: 'Arun Kumar',
        category: 'Tester', demoData: data)));
    await tester.pump();

    expect(find.text('MY DASHBOARD'), findsOneWidget);
    expect(find.text('6-day on-time streak'), findsOneWidget);
    expect(find.text('Hours per week'), findsOneWidget);
    expect(find.text('2.5h'), findsOneWidget);                 // overtime
    expect(find.textContaining('of 12 left', findRichText: true), findsOneWidget);
    expect(find.text('4 used · 1 waiting for approval'), findsOneWidget);
    expect(find.text('Perfect week'), findsOneWidget);
    expect(find.text('Fire drill Friday'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Mira'), findsOneWidget);
    expect(find.text('Founders day'), findsOneWidget);
    expect(find.text('Show QR code'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  test('Only super admins can change things; faces need the desktop app', () {
    ApiService.setSession('t', 1, 'viewer', 'HR');
    expect(ApiService.canEdit, isFalse);
    expect(ApiService.canRegisterFaces, isFalse);
    ApiService.setSession('t', 1, 'admin', 'Boss');
    expect(ApiService.canEdit, isTrue);
    expect(ApiService.canRegisterFaces, isTrue); // tests run on the desktop VM, not web
    ApiService.clearSession();
  });
}
