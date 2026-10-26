import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// One person at a glance: month calendar, stats, face status, leave history.
class EmployeeProfileView extends StatefulWidget {
  final int employeeId;
  final int revision; // changes when the dashboard edited this person → reload
  final VoidCallback onBack;
  final void Function(Employee) onEdit;
  final void Function(Employee, {bool replace}) onRegisterFace;
  const EmployeeProfileView({super.key, required this.employeeId, this.revision = 0, required this.onBack,
      required this.onEdit, required this.onRegisterFace});

  @override
  State<EmployeeProfileView> createState() => _EmployeeProfileViewState();
}

class _EmployeeProfileViewState extends State<EmployeeProfileView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EmployeeProfileView old) {
    super.didUpdateWidget(old);
    if (old.employeeId != widget.employeeId || old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    try {
      final p = await ApiService.getProfile(widget.employeeId, _month.year, _month.month);
      if (mounted) setState(() { _p = p; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load this employee: $e');
    }
  }

  void _shift(int months) {
    final next = DateTime(_month.year, _month.month + months);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('All employees'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary)),
      ),
      const SizedBox(height: 8),
      if (_error != null) InfoBanner(_error!),
      if (p == null && _error == null)
        const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
      if (p != null) ..._content(p),
    ]);
  }

  List<Widget> _content(Map<String, dynamic> p) {
    final emp = Employee.fromJson(Map<String, dynamic>.from(p['employee']));
    final row = p['row'] == null ? null : Map<String, dynamic>.from(p['row']);
    final t = row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row['totals']);
    final faces = p['face_photos'] as int;
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return [
      AppCard(
        child: Row(children: [
          InitialsAvatar(emp.name, size: 64),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(emp.name, style: AppTheme.h1),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                emp.category == null
                    ? const StatusBadge('No team', tone: Tone.warning)
                    : StatusBadge(emp.category!, tone: Tone.neutral, dot: false),
                StatusBadge(emp.isActive ? 'Can check in' : 'Disabled', tone: emp.isActive ? Tone.success : Tone.neutral),
                faces > 0
                    ? StatusBadge('Face registered · $faces photos', tone: Tone.success)
                    : const StatusBadge('Face not registered', tone: Tone.warning),
              ]),
            ]),
          ),
          if (ApiService.canEdit)
            OutlinedButton.icon(onPressed: () => widget.onEdit(emp), icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit details')),
          if (ApiService.canRegisterFaces) ...[
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () => widget.onRegisterFace(emp, replace: faces > 0),
              icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
              label: Text(faces > 0 ? 'Re-register face' : 'Register face'),
            ),
          ],
        ]),
      ),
      const SizedBox(height: AppTheme.gap),
      Row(children: [
        IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous month'),
        SizedBox(width: 150, child: Text(DateFormat('MMMM y').format(_month), textAlign: TextAlign.center, style: AppTheme.h3)),
        IconButton(onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right), tooltip: 'Next month'),
      ]),
      const SizedBox(height: 8),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: StatCard(label: 'Attendance', value: row?['attendance_pct'] == null ? '—' : '${(row!['attendance_pct'] as num).round()}%',
            icon: Icons.how_to_reg_outlined, tone: Tone.success,
            caption: '${(t['present'] ?? 0) + (t['late'] ?? 0) + (t['half_day'] ?? 0)} days present')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Late', value: '${t['late'] ?? 0}',
            icon: Icons.schedule_outlined, tone: (t['late'] ?? 0) > 0 ? Tone.warning : Tone.neutral,
            caption: (row?['late_minutes'] ?? 0) > 0 ? '${formatMinutes(row!['late_minutes'])} late in total' : 'Always on time')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Absent', value: '${t['absent'] ?? 0}',
            icon: Icons.event_busy_outlined, tone: (t['absent'] ?? 0) > 0 ? Tone.danger : Tone.neutral,
            caption: '${t['leave'] ?? 0} on leave')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Hours worked', value: '${row?['worked_hours'] ?? 0}h',
            icon: Icons.timelapse, tone: Tone.primary,
            caption: (row?['overtime_hours'] ?? 0) > 0
                ? '${row!['overtime_hours']}h overtime · shift ${row['shift']}'
                : 'Shift ${row?['shift'] ?? ''}')),
      ])),
      const SizedBox(height: AppTheme.gap),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _calendar(p, row)),
        const SizedBox(width: AppTheme.gap),
        Expanded(flex: 2, child: _leave((p['leave'] as List).cast<Map<String, dynamic>>())),
      ]),
    ];
  }

  Widget _calendar(Map<String, dynamic> p, Map<String, dynamic>? row) {
    final days = (p['month']['days'] as List).cast<Map<String, dynamic>>();
    final cells = row == null ? const [] : row['cells'] as List;
    final firstWeekday = DateTime.parse(days.first['date']).weekday; // 1 = Monday
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Calendar', style: AppTheme.h3),
        const SizedBox(height: 4),
        Text('Office hours ${p['month']['work_start']}–${p['month']['work_end']}', style: AppTheme.muted),
        const SizedBox(height: 16),
        Row(children: [
          for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
            Expanded(child: Text(d, textAlign: TextAlign.center, style: AppTheme.overline)),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth / 7;
          final slots = firstWeekday - 1 + days.length;
          return Wrap(children: [
            for (var i = 0; i < slots; i++)
              SizedBox(
                width: w, height: 64,
                child: i < firstWeekday - 1 ? null : Padding(
                  padding: const EdgeInsets.all(3),
                  child: _dayTile(days[i - firstWeekday + 1],
                      cells.isEmpty ? {'status': 'future'} : Map<String, dynamic>.from(cells[i - firstWeekday + 1]),
                      today),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 14),
        const DayLegend(),
      ]),
    );
  }

  Widget _dayTile(Map<String, dynamic> day, Map<String, dynamic> cell, String today) {
    final (bg, fg, _, label) = DayStatus.of(cell['status']);
    final isToday = day['date'] == today;
    final sub = switch (cell['status']) {
      'present' || 'late' || 'half_day' => cell['in'] as String,
      'holiday' => 'Holiday',
      'leave' => 'Leave',
      'absent' => 'Absent',
      _ => '',
    };
    return Tooltip(
      message: '${DateFormat('EEEE, d MMM').format(DateTime.parse(day['date']))}\n$label'
          '${cell['in'] != null ? ' · in ${cell['in']}${cell['out'] != null ? ', out ${cell['out']}' : ''}' : ''}'
          '${cell['name'] != null ? ' · ${cell['name']}' : ''}',
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isToday ? AppTheme.primary : Colors.transparent, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${day['day']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: isToday ? AppTheme.primary : AppTheme.textPrimary)),
          const Spacer(),
          Text(sub, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg), overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _leave(List<Map<String, dynamic>> leave) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Leave', style: AppTheme.h3),
          const SizedBox(height: 12),
          if (leave.isEmpty) Text('No leave taken or requested.', style: AppTheme.muted),
          for (final l in leave) ...[
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_dates(DateTime.parse(l['start_date']), DateTime.parse(l['end_date'])),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('${_kind(l['kind'])}${(l['reason'] as String).isEmpty ? '' : ' · ${l['reason']}'}',
                    style: AppTheme.muted, overflow: TextOverflow.ellipsis),
              ])),
              StatusBadge((l['status'] as String)[0].toUpperCase() + (l['status'] as String).substring(1),
                  tone: switch (l['status']) { 'approved' => Tone.success, 'rejected' => Tone.danger, _ => Tone.warning }),
            ]),
            const SizedBox(height: 12),
          ],
        ]),
      );
}

String _dates(DateTime a, DateTime b) {
  final f = DateFormat('d MMM');
  return a == b ? DateFormat('EEE, d MMM y').format(a) : '${f.format(a)} – ${DateFormat('d MMM y').format(b)}';
}

String _kind(String k) => switch (k) { 'sick' => 'Sick leave', 'casual' => 'Casual leave', _ => 'Other leave' };
