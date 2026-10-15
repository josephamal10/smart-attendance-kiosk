import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Every admin change and automatic system action: who, when, what, why.
class AuditPage extends StatefulWidget {
  final List<Employee> employees;
  const AuditPage({super.key, required this.employees});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  List<AuditEntry> _entries = [];
  bool _loading = true;
  String _query = '';

  static const _labels = {
    'attendance.corrected': ('Attendance corrected', Icons.edit_calendar_outlined, Tone.warning),
    'attendance.added': ('Attendance added', Icons.add_circle_outline, Tone.primary),
    'attendance.auto_checkout': ('Auto check-out', Icons.nightlight_outlined, Tone.neutral),
    'employee.added': ('Employee added', Icons.person_add_alt_1_outlined, Tone.success),
    'employee.updated': ('Employee updated', Icons.manage_accounts_outlined, Tone.primary),
    'faces.deleted': ('Face data deleted', Icons.face_retouching_off, Tone.danger),
    'holiday.added': ('Holiday added', Icons.celebration_outlined, Tone.primary),
    'holiday.removed': ('Holiday removed', Icons.event_busy_outlined, Tone.neutral),
    'leave.added': ('Leave recorded', Icons.beach_access_outlined, Tone.primary),
    'leave.approved': ('Leave approved', Icons.check_circle_outline, Tone.success),
    'leave.rejected': ('Leave rejected', Icons.cancel_outlined, Tone.danger),
    'correction.resolved': ('Request resolved', Icons.task_alt, Tone.success),
    'correction.rejected': ('Request rejected', Icons.cancel_outlined, Tone.danger),
    'settings.updated': ('Settings changed', Icons.tune, Tone.primary),
    'email.daily_summary': ('Daily email', Icons.mail_outline, Tone.neutral),
    'email.test': ('Test email', Icons.mail_outline, Tone.neutral),
    'backup.created': ('Backup made', Icons.backup_outlined, Tone.neutral),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await ApiService.getAudit();
      if (mounted) setState(() => _entries = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _empName(int? id) =>
      id == null ? '' : widget.employees.where((e) => e.id == id).map((e) => e.name).firstOrNull ?? 'Employee #$id';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = _entries.where((e) => q.isEmpty
        || '${e.actorName} ${e.action} ${e.details} ${e.reason} ${_empName(e.employeeId)}'.toLowerCase().contains(q)).toList();
    return DataCard(
      header: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Activity', style: AppTheme.h3),
          const SizedBox(height: 2),
          Text('Every change made in the dashboard and by the system. Entries cannot be edited.', style: AppTheme.muted),
        ])),
        if (_loading) const Padding(padding: EdgeInsets.only(right: 12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        SizedBox(
          width: 280,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(hintText: 'Search activity', prefixIcon: Icon(Icons.search, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10)),
          ),
        ),
      ]),
      empty: const EmptyState(icon: Icons.history, title: 'No activity yet',
          message: 'Changes like corrections, approvals and settings will be listed here.'),
      columns: const [Col('When', flex: 2), Col('Action', flex: 3), Col('Employee', flex: 2),
          Col('Details', flex: 4), Col('By', flex: 2)],
      rows: [
        for (final e in shown)
          [
            Text(DateFormat('d MMM, h:mm a').format(e.at), style: AppTheme.muted),
            Builder(builder: (_) {
              final (label, icon, tone) = _labels[e.action] ?? (e.action, Icons.circle_outlined, Tone.neutral);
              return Row(children: [
                Icon(icon, size: 18, color: tone.fg),
                const SizedBox(width: 8),
                Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]);
            }),
            Text(_empName(e.employeeId).isEmpty ? '—' : _empName(e.employeeId), style: AppTheme.body),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(e.details.isEmpty ? '—' : e.details, style: AppTheme.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (e.reason.isNotEmpty)
                Text('Reason: ${e.reason}', style: AppTheme.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
            Text(e.actorName, style: AppTheme.body),
          ],
      ],
    );
  }
}
