import 'package:flutter/material.dart';
import '../screens/my_attendance_screen.dart';
import '../services/api_service.dart';
import '../services/demo.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Opens an employee's own dashboard in demo mode (no face scan needed).
Future<void> openDemoDashboard(BuildContext context, Map<String, dynamic> employee) async {
  try {
    final r = await ApiService.demoDashboard(employee['id'] as int);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        MyAttendanceScreen(token: r['self_token'], name: r['name'], category: r['category'])));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the demo dashboard: $e'), backgroundColor: AppTheme.danger));
    }
  }
}

/// "Try the demo" box on the admin sign-in page: demo accounts with a Use button, and
/// employees whose dashboards visitors can open. Only shown when the server runs in demo mode.
class DemoPanel extends StatelessWidget {
  final void Function(String username, String password) onUseAccount;
  const DemoPanel({super.key, required this.onUseAccount});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: Demo.info,
        builder: (context, info, _) {
          if (info == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(top: 28),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.play_circle_outline, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('TRY THE DEMO', style: AppTheme.overline.copyWith(color: AppTheme.primary)),
              ]),
              const SizedBox(height: 6),
              Text('Made-up company data. Sign in with an account below, or open an employee\'s own '
                  'dashboard (at the real kiosk that takes a face scan).', style: AppTheme.muted),
              const SizedBox(height: 14),
              for (final a in Demo.accounts) ...[
                _account(a),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              Text('Employee dashboards', style: AppTheme.label),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in Demo.employees.take(6))
                  ActionChip(
                    avatar: InitialsAvatar(e['name'], size: 22),
                    label: Text(e['name']),
                    tooltip: 'Open ${e['name']}\'s dashboard (${e['category'] ?? 'no team'})',
                    onPressed: () => openDemoDashboard(context, e),
                    backgroundColor: AppTheme.surface,
                    side: BorderSide(color: AppTheme.border),
                  ),
              ]),
            ]),
          );
        },
      );

  Widget _account(Map<String, dynamic> a) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['role'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            SelectableText('${a['username']}  ·  ${a['password']}',
                style: AppTheme.muted.copyWith(fontFeatures: AppTheme.tabular)),
          ])),
          TextButton(onPressed: () => onUseAccount(a['username'], a['password']), child: const Text('Use')),
        ]),
      );
}
