import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'attendance_edit_dialog.dart';

/// Leave requests and "my attendance is wrong" reports sent from the kiosk.
class RequestsPage extends StatefulWidget {
  final List<Employee> employees;
  final VoidCallback onChanged; // refresh dashboard counts after a decision
  const RequestsPage({super.key, required this.employees, required this.onChanged});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  String _tab = 'leave';
  List<LeaveRequest> _leave = [];
  List<CorrectionRequest> _corrections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([ApiService.getLeave(), ApiService.getCorrections()]);
      if (!mounted) return;
      setState(() {
        _leave = r[0] as List<LeaveRequest>;
        _corrections = r[1] as List<CorrectionRequest>;
      });
    } catch (e) {
      if (mounted) _toast('Could not load requests: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppTheme.danger : null));

  Employee? _emp(int id) => widget.employees.where((e) => e.id == id).firstOrNull;

  Future<void> _decideLeave(LeaveRequest l, bool approve) async {
    try {
      await ApiService.decideLeave(l.id, approve);
      _toast(approve ? 'Leave approved for ${_emp(l.employeeId)?.name}.' : 'Leave rejected.');
      widget.onChanged();
      _load();
    } catch (e) {
      _toast('Failed: $e', error: true);
    }
  }

  Future<void> _fixCorrection(CorrectionRequest c) async {
    // Find the record for that day (if any), then open the correction dialog
    final day = ApiService.ymd(c.date);
    AttendanceLog? log;
    try {
      log = (await ApiService.getAllAttendance(start: day, end: day))
          .where((l) => l.employeeId == c.employeeId).firstOrNull;
    } catch (_) {}
    if (!mounted) return;
    final saved = await showDialog<AttendanceLog>(
      context: context,
      builder: (_) => AttendanceEditDialog(
        log: log, employees: widget.employees, employeeId: c.employeeId, date: c.date,
        suggestedReason: 'Employee request: ${c.note.isEmpty ? _kindLabel(c.kind) : c.note}',
      ),
    );
    if (saved == null) return;
    try {
      await ApiService.decideCorrection(c.id, true);
    } catch (_) {}
    _toast('Record fixed and request marked resolved.');
    widget.onChanged();
    _load();
  }

  Future<void> _rejectCorrection(CorrectionRequest c) async {
    try {
      await ApiService.decideCorrection(c.id, false);
      widget.onChanged();
      _load();
    } catch (e) {
      _toast('Failed: $e', error: true);
    }
  }

  Future<void> _recordLeave() async {
    final ok = await showDialog<bool>(context: context,
        builder: (_) => _RecordLeaveDialog(employees: widget.employees));
    if (ok == true) {
      _toast('Leave recorded.');
      widget.onChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingLeave = _leave.where((l) => l.status == 'pending').length;
    final pendingFix = _corrections.where((c) => c.status == 'pending').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'leave', label: Text('Leave${pendingLeave > 0 ? '  ($pendingLeave)' : ''}'),
                icon: const Icon(Icons.beach_access_outlined)),
            ButtonSegment(value: 'fix', label: Text('Corrections${pendingFix > 0 ? '  ($pendingFix)' : ''}'),
                icon: const Icon(Icons.build_outlined)),
          ],
          selected: {_tab},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const Spacer(),
        if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        if (_tab == 'leave')
          OutlinedButton.icon(onPressed: _recordLeave, icon: const Icon(Icons.add, size: 18),
              label: const Text('Record leave')),
      ]),
      const SizedBox(height: 16),
      if (_tab == 'leave') _leaveTable() else _correctionTable(),
    ]);
  }

  Widget _leaveTable() {
    final sorted = [..._leave]..sort((a, b) {
        final p = (a.status == 'pending' ? 0 : 1) - (b.status == 'pending' ? 0 : 1);
        return p != 0 ? p : b.createdAt.compareTo(a.createdAt);
      });
    return DataCard(
      header: Text('Leave requests', style: AppTheme.h3),
      empty: const EmptyState(icon: Icons.beach_access_outlined, title: 'No leave requests',
          message: 'Employees can request leave from "My attendance" at the kiosk.'),
      columns: const [Col('Employee', flex: 3), Col('Dates', flex: 3), Col('Type', flex: 2),
          Col('Reason', flex: 3), Col('Status', flex: 2), Col('', flex: 3, alignEnd: true)],
      rows: [
        for (final l in sorted)
          [
            PersonCell(_emp(l.employeeId)?.name ?? 'Former employee', secondary: _emp(l.employeeId)?.category),
            Text('${_dates(l.startDate, l.endDate)}\n${l.days} day${l.days == 1 ? '' : 's'}', style: AppTheme.body),
            Text(_leaveKind(l.kind), style: AppTheme.body),
            Text(l.reason.isEmpty ? '—' : l.reason, style: AppTheme.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
            _statusBadge(l.status),
            l.status != 'pending'
                ? const SizedBox.shrink()
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    OutlinedButton(onPressed: () => _decideLeave(l, false), child: const Text('Reject')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () => _decideLeave(l, true), child: const Text('Approve')),
                  ]),
          ],
      ],
    );
  }

  Widget _correctionTable() {
    final sorted = [..._corrections]..sort((a, b) {
        final p = (a.status == 'pending' ? 0 : 1) - (b.status == 'pending' ? 0 : 1);
        return p != 0 ? p : b.createdAt.compareTo(a.createdAt);
      });
    return DataCard(
      header: Text('Correction requests', style: AppTheme.h3),
      empty: const EmptyState(icon: Icons.build_outlined, title: 'Nothing to fix',
          message: 'Employees can report a wrong or missing check-out from "My attendance".'),
      columns: const [Col('Employee', flex: 3), Col('Day', flex: 2), Col('Problem', flex: 2),
          Col('Details', flex: 4), Col('Status', flex: 2), Col('', flex: 3, alignEnd: true)],
      rows: [
        for (final c in sorted)
          [
            PersonCell(_emp(c.employeeId)?.name ?? 'Former employee', secondary: _emp(c.employeeId)?.category),
            Text(DateFormat('EEE, d MMM').format(c.date), style: AppTheme.body),
            Text(_kindLabel(c.kind), style: AppTheme.body),
            Text(c.note.isEmpty ? '—' : c.note, style: AppTheme.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
            _statusBadge(c.status),
            c.status != 'pending'
                ? const SizedBox.shrink()
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    OutlinedButton(onPressed: () => _rejectCorrection(c), child: const Text('Reject')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () => _fixCorrection(c), child: const Text('Fix record')),
                  ]),
          ],
      ],
    );
  }
}

Widget _statusBadge(String status) => StatusBadge(
      status[0].toUpperCase() + status.substring(1),
      tone: switch (status) {
        'approved' || 'resolved' => Tone.success,
        'rejected' => Tone.danger,
        _ => Tone.warning,
      },
    );

String _dates(DateTime a, DateTime b) {
  final f = DateFormat('d MMM');
  return a == b ? DateFormat('EEE, d MMM').format(a) : '${f.format(a)} – ${f.format(b)}';
}

String _leaveKind(String k) => switch (k) { 'sick' => 'Sick', 'casual' => 'Casual', _ => 'Other' };
String _kindLabel(String k) =>
    switch (k) { 'missed_checkout' => 'Forgot check-out', 'wrong_time' => 'Wrong time', _ => 'Other' };

class _RecordLeaveDialog extends StatefulWidget {
  final List<Employee> employees;
  const _RecordLeaveDialog({required this.employees});
  @override
  State<_RecordLeaveDialog> createState() => _RecordLeaveDialogState();
}

class _RecordLeaveDialogState extends State<_RecordLeaveDialog> {
  int? _employeeId;
  DateTimeRange? _range;
  String _kind = 'casual';
  final _reason = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employeeId == null || _range == null) {
      setState(() => _error = 'Choose the employee and the dates.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.addLeave(_employeeId!, _range!.start, _range!.end, _kind, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Record leave'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Recorded leave is approved straight away.', style: AppTheme.muted),
            const SizedBox(height: 16),
            Text('Employee', style: AppTheme.label),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _employeeId,
              isExpanded: true,
              hint: const Text('Choose a person'),
              items: [for (final e in widget.employees) DropdownMenuItem(value: e.id, child: Text(e.name))],
              onChanged: (v) => setState(() => _employeeId = v),
            ),
            const SizedBox(height: 16),
            Text('Dates', style: AppTheme.label),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final r = await showDateRangePicker(context: context,
                    firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 365)),
                    initialDateRange: _range,
                    builder: (ctx, child) => Center(child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640), child: child)));
                if (r != null) setState(() => _range = r);
              },
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_range == null ? 'Choose dates' : _dates(_range!.start, _range!.end)),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'casual', label: Text('Casual')),
                ButtonSegment(value: 'sick', label: Text('Sick')),
                ButtonSegment(value: 'other', label: Text('Other')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            TextField(controller: _reason, decoration: const InputDecoration(hintText: 'Reason (optional)')),
            if (_error != null) ...[const SizedBox(height: 14), InfoBanner(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Record leave')),
        ],
      );
}
