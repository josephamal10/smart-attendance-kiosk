// Dev tool: renders any screen against the demo server so README screenshots can be
// captured automatically (see scripts/screenshots.py). Not part of the kiosk app.
//
//   ?screen=dashboard&page=analytics&dark=1
//   ?screen=dashboard&page=attendance:register
//   ?screen=profile&id=3      ?screen=lock      ?screen=kiosk      ?screen=login      ?screen=me
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../i18n/kiosk_text.dart';
import '../screens/admin_dashboard.dart';
import '../screens/admin_login_screen.dart';
import '../screens/kiosk_screen.dart';
import '../screens/lock_screen.dart';
import '../screens/my_attendance_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/branding.dart';

const _adminToken = String.fromEnvironment('DEMO_TOKEN');
const _selfToken = String.fromEnvironment('SELF_TOKEN');

Future<void> main() async {
  final q = Uri.base.queryParameters;
  await initializeDateFormatting();
  KioskText.lang.value = KioskLang.values.firstWhere((l) => l.name == q['lang'], orElse: () => KioskLang.en);
  AppTheme.isDark = q['dark'] == '1';
  ApiService.setSession(_adminToken, 1, 'admin', 'Demo Admin');
  Branding.load();
  LockScreen.pollServer = false;
  final Widget home = switch (q['screen']) {
    'lock' => const LockScreen(),
    'kiosk' => KioskScreen(demoResult: {
        'recognized': true, 'name': 'Priya Raman', 'category': 'HR', 'action': 'in',
        'time': DateTime.now().copyWith(hour: 9, minute: 12).toIso8601String(), 'greeting': 'Good morning, Priya!',
        'flags': const <String>[], 'message': 'Have a great day!', 'self_token': 'demo',
      }),
    'login' => const AdminLoginScreen(),
    'me' => const MyAttendanceScreen(token: _selfToken, name: 'Priya Raman', category: 'HR'),
    'profile' => AdminDashboard(initialProfileId: int.tryParse(q['id'] ?? '')),
    _ => AdminDashboard(initialPage: q['page']),
  };
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.theme, home: home));
}
