import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Monthly attendance register: everyone × every day, with totals — what HR uses for payroll.
class RegisterView extends StatefulWidget {
  final void Function(int employeeId) onOpenEmployee;
  const RegisterView({super.key, required this.onOpenEmployee});
  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _exporting = false;
  String? _team;

  static const _cell = 28.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiService.getRegister(_month.year, _month.month);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load register: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int months) {
    final next = DateTime(_month.year, _month.month + months);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    _load();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await ApiService.downloadRegisterXlsx(_month.year, _month.month);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel saved to $path')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e'), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final d = _data;
    final rows = d == null
        ? const <Map<String, dynamic>>[]
        : (d['rows'] as List).cast<Map<String, dynamic>>()
            .where((r) => _team == null || (r['category'] ?? 'No team') == _team).toList();
    final teams = d == null
        ? const <String>[]
        : {for (final r in (d['rows'] as List)) (r['category'] ?? 'No team') as String}.toList();

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Previous month'),
            SizedBox(width: 150, child: Text(DateFormat('MMMM y').format(_month),
                textAlign: TextAlign.center, style: AppTheme.h3)),
            IconButton(onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right),
                tooltip: 'Next month'),
            if (_loading) const Padding(padding: EdgeInsets.only(left: 8),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            const Spacer(),
            if (teams.length > 1)
              DropdownButton<String?>(
                value: _team,
                underline: const SizedBox.shrink(),
                hint: const Text('All teams'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All teams')),
                  for (final t in teams) DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _team = v),
              ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _exporting || d == null ? null : _export,
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.table_view_outlined, size: 18),
              label: const Text('Export Excel'),
            ),
          ]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 14), child: DayLegend()),
        const Divider(),
        if (d == null)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          const EmptyState(icon: Icons.grid_on, title: 'No employees', message: 'Nobody to show for this filter.')
        else
          Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _grid(d, rows),
            ),
          ),
      ]),
    );
  }

  Widget _grid(Map<String, dynamic> d, List<Map<String, dynamic>> rows) {
    final days = (d['days'] as List).cast<Map<String, dynamic>>();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    TextStyle head = AppTheme.overline.copyWith(fontSize: 10, letterSpacing: 0);

    Widget totalHead(String t) => SizedBox(width: 44, child: Text(t, textAlign: TextAlign.center, style: head));
    Widget total(String t, {Color? color}) => SizedBox(width: 44, child: Text(t, textAlign: TextAlign.center,
        style: AppTheme.body.copyWith(fontWeight: FontWeight.w600, color: color, fontFeatures: AppTheme.tabular)));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(width: 190, child: Text('EMPLOYEE', style: head)),
        for (final day in days)
          Container(
            width: _cell + 2,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: day['date'] == today
                ? BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(6))
                : null,
            child: Column(children: [
              Text((day['weekday'] as String).substring(0, 2), style: head.copyWith(
                  color: day['working'] == true ? AppTheme.textMuted : AppTheme.textMuted.withValues(alpha: 0.5))),
              Text('${day['day']}', style: AppTheme.label.copyWith(fontFeatures: AppTheme.tabular,
                  color: day['date'] == today ? AppTheme.primary : null)),
            ]),
          ),
        const SizedBox(width: 12),
        totalHead('P'), totalHead('LATE'), totalHead('ABS'), totalHead('LEAVE'), totalHead('OT h'), totalHead('%'),
      ]),
      const SizedBox(height: 6),
      for (final r in rows)
        InkWell(
          onTap: () => widget.onOpenEmployee(r['employee_id'] as int),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 190, child: PersonCell(r['name'], secondary: r['category'] ?? 'No team')),
              for (var i = 0; i < days.length; i++) _dayCell(days[i], (r['cells'] as List)[i]),
              const SizedBox(width: 12),
              total('${(r['totals']['present'] as int) + (r['totals']['late'] as int) + (r['totals']['half_day'] as int)}'),
              total('${r['totals']['late']}', color: (r['totals']['late'] as int) > 0 ? AppTheme.warning : null),
              total('${r['totals']['absent']}', color: (r['totals']['absent'] as int) > 0 ? AppTheme.danger : null),
              total('${r['totals']['leave']}'),
              total((r['overtime_hours'] ?? 0) == 0 ? '—' : '${r['overtime_hours']}',
                  color: (r['overtime_hours'] ?? 0) > 0 ? AppTheme.primary : null),
              total(r['attendance_pct'] == null ? '—' : '${(r['attendance_pct'] as num).round()}'),
            ]),
          ),
        ),
    ]);
  }

  Widget _dayCell(Map<String, dynamic> day, Map cell) {
    final status = cell['status'] as String;
    final (bg, fg, code, label) = DayStatus.of(status);
    final date = DateFormat('EEE, d MMM').format(DateTime.parse(day['date']));
    final detail = switch (status) {
      'present' || 'late' || 'half_day' => '$label · in ${cell['in']}${cell['out'] == null ? '' : ', out ${cell['out']}'}',
      'holiday' => 'Holiday: ${cell['name']}',
      _ => label,
    };
    return Tooltip(
      message: '$date\n$detail',
      waitDuration: const Duration(milliseconds: 250),
      child: Container(
        width: _cell, height: _cell,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: status == 'future' ? Border.all(color: AppTheme.border) : null,
        ),
        child: Text(code, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
