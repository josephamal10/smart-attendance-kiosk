import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// An employee's own page, opened from the kiosk right after their face check-in.
/// No password: the check-in gave a short-lived token for this one person.
/// Closes itself after a minute without touches so the next person can't see it.
class MyAttendanceScreen extends StatefulWidget {
  final String token;
  final String name;
  final String? category;
  const MyAttendanceScreen({super.key, required this.token, required this.name, this.category});

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  static const _idleSeconds = 60;
  Map<String, dynamic>? _data;
  String? _error;
  int _secondsLeft = _idleSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _close();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    _timer?.cancel();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _touched() {
    if (_secondsLeft != _idleSeconds) setState(() => _secondsLeft = _idleSeconds);
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.mySummary(widget.token);
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Can't reach the attendance server.");
    }
  }

  void _toast(String msg, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppTheme.danger : null));

  Future<void> _requestLeave() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _LeaveDialog(token: widget.token));
    if (ok == true && mounted) {
      _toast('Leave request sent. The admin will approve or reject it.');
      _load();
    }
  }

  Future<void> _reportProblem() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ProblemDialog(token: widget.token));
    if (ok == true && mounted) _toast('Thanks. The admin will check and fix your record.');
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _touched(),
      child: Scaffold(
        body: Column(children: [
          _header(),
          Expanded(
            child: _error != null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    EmptyState(icon: Icons.lock_clock_outlined, title: 'Please scan again', message: _error!),
                    ElevatedButton(onPressed: _close, child: const Text('Back to kiosk')),
                  ]))
                : _data == null
                    ? const Center(child: CircularProgressIndicator())
                    : _body(_data!),
          ),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          InitialsAvatar(widget.name, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My attendance', style: AppTheme.overline),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(child: Text(widget.name, style: AppTheme.h2, overflow: TextOverflow.ellipsis)),
                if (widget.category != null) ...[
                  const SizedBox(width: 10),
                  StatusBadge(widget.category!, tone: Tone.neutral, dot: false),
                ],
              ]),
            ]),
          ),
          Text('Closes in $_secondsLeft s', style: AppTheme.muted.copyWith(fontFeatures: AppTheme.tabular)),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Done'),
          ),
        ]),
      );

  Widget _body(Map<String, dynamic> d) {
    final m = Map<String, dynamic>.from(d['month']);
    final recent = (d['recent'] as List).cast<Map<String, dynamic>>();
    final leave = (d['leave_requests'] as List).cast<Map<String, dynamic>>();
    final avg = m['avg_hours'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('This month', style: AppTheme.h3),
        const SizedBox(height: 12),
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: StatCard(label: 'Days present', value: '${m['present']}',
              icon: Icons.how_to_reg_outlined, tone: Tone.success,
              caption: 'of ${m['working_days']} working days')),
          const SizedBox(width: AppTheme.gap),
          Expanded(child: StatCard(label: 'Late', value: '${m['late']}',
              icon: Icons.schedule_outlined, tone: m['late'] > 0 ? Tone.warning : Tone.neutral)),
          const SizedBox(width: AppTheme.gap),
          Expanded(child: StatCard(label: 'On leave', value: '${m['leave']}',
              icon: Icons.beach_access_outlined, tone: Tone.primary)),
          const SizedBox(width: AppTheme.gap),
          Expanded(child: StatCard(label: 'Average day', value: avg == null ? '—' : '${avg}h',
              icon: Icons.timelapse, tone: Tone.neutral,
              caption: m['absent'] > 0 ? '${m['absent']} day(s) absent' : 'No absences')),
        ])),
        const SizedBox(height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _recentCard(recent)),
          const SizedBox(width: AppTheme.gap),
          Expanded(flex: 2, child: Column(children: [_actionsCard(), const SizedBox(height: AppTheme.gap), _leaveCard(leave)])),
        ]),
      ]),
    );
  }

  Widget _recentCard(List<Map<String, dynamic>> recent) {
    final t = DateFormat('h:mm a');
    return DataCard(
      header: Text('Recent days', style: AppTheme.h3),
      empty: const EmptyState(icon: Icons.event_busy_outlined, title: 'No records yet',
          message: 'Your check-ins will show up here.'),
      columns: const [Col('Date', flex: 3), Col('In', flex: 2), Col('Out', flex: 2), Col('Hours', flex: 2), Col('', flex: 3)],
      rows: [
        for (final r in recent)
          [
            Text(DateFormat('EEE, d MMM').format(DateTime.parse(r['date'])), style: AppTheme.body),
            Text(r['in_time'] == null ? '—' : t.format(DateTime.parse(r['in_time'])), style: AppTheme.body),
            Text(r['out_time'] == null ? '—' : t.format(DateTime.parse(r['out_time'])), style: AppTheme.body),
            Text(r['worked_minutes'] == null ? '—' : formatMinutes(r['worked_minutes']), style: AppTheme.body),
            FlagBadges(
              flags: (r['flags'] as List).cast<String>(),
              lateMinutes: r['late_minutes'] ?? 0,
              earlyMinutes: r['early_minutes'] ?? 0,
              whenClean: const StatusBadge('On time', tone: Tone.success),
            ),
          ],
      ],
    );
  }

  Widget _actionsCard() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Need something?', style: AppTheme.h3),
          const SizedBox(height: 4),
          Text('Requests go to the admin for approval.', style: AppTheme.muted),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _requestLeave,
            icon: const Icon(Icons.beach_access_outlined, size: 18),
            label: const Text('Request leave'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _reportProblem,
            icon: const Icon(Icons.report_outlined, size: 18),
            label: const Text('Report a problem with my attendance'),
          ),
        ]),
      );

  Widget _leaveCard(List<Map<String, dynamic>> leave) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('My leave requests', style: AppTheme.h3),
          const SizedBox(height: 12),
          if (leave.isEmpty) Text('None yet.', style: AppTheme.muted),
          for (final l in leave) ...[
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_range(DateTime.parse(l['start_date']), DateTime.parse(l['end_date'])),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(_kind(l['kind']), style: AppTheme.muted),
                ]),
              ),
              StatusBadge(_cap(l['status']), tone: switch (l['status']) {
                'approved' => Tone.success,
                'rejected' => Tone.danger,
                _ => Tone.warning,
              }),
            ]),
            const SizedBox(height: 10),
          ],
        ]),
      );
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String _kind(String k) => switch (k) { 'sick' => 'Sick leave', 'casual' => 'Casual leave', _ => 'Other leave' };
String _range(DateTime a, DateTime b) {
  final f = DateFormat('d MMM');
  return a == b ? DateFormat('EEE, d MMM').format(a) : '${f.format(a)} – ${f.format(b)}';
}

// ── Dialogs ──────────────────────────────────────────────────

class _LeaveDialog extends StatefulWidget {
  final String token;
  const _LeaveDialog({required this.token});
  @override
  State<_LeaveDialog> createState() => _LeaveDialogState();
}

class _LeaveDialogState extends State<_LeaveDialog> {
  DateTimeRange? _range;
  String _kind = 'casual';
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _range,
      builder: (ctx, child) => Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640), child: child)),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _send() async {
    if (_range == null) {
      setState(() => _error = 'Choose the dates first.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.requestLeave(widget.token, _range!.start, _range!.end, _kind, _reason.text.trim());
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
        title: const Text('Request leave'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Dates', style: AppTheme.label),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_range == null ? 'Choose dates' : _rangeText(_range!)),
            ),
            const SizedBox(height: 16),
            Text('Type', style: AppTheme.label),
            const SizedBox(height: 6),
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
            Text('Reason (optional)', style: AppTheme.label),
            const SizedBox(height: 6),
            TextField(controller: _reason, maxLines: 2, decoration: const InputDecoration(hintText: 'e.g. Family function')),
            if (_error != null) ...[const SizedBox(height: 14), InfoBanner(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _saving ? null : _send, child: const Text('Send request')),
        ],
      );
}

String _rangeText(DateTimeRange r) {
  final f = DateFormat('d MMM y');
  final days = r.end.difference(r.start).inDays + 1;
  return '${f.format(r.start)} – ${f.format(r.end)}  ($days day${days == 1 ? '' : 's'})';
}

class _ProblemDialog extends StatefulWidget {
  final String token;
  const _ProblemDialog({required this.token});
  @override
  State<_ProblemDialog> createState() => _ProblemDialogState();
}

class _ProblemDialogState extends State<_ProblemDialog> {
  DateTime _date = DateTime.now();
  String _kind = 'missed_checkout';
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.reportProblem(widget.token, _date, _kind, _note.text.trim());
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
        title: const Text('Report a problem'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Which day?', style: AppTheme.label),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(DateFormat('EEEE, d MMM y').format(_date)),
            ),
            const SizedBox(height: 16),
            Text('What happened?', style: AppTheme.label),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'missed_checkout', label: Text('Forgot check-out')),
                ButtonSegment(value: 'wrong_time', label: Text('Wrong time')),
                ButtonSegment(value: 'other', label: Text('Other')),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            Text('Details', style: AppTheme.label),
            const SizedBox(height: 6),
            TextField(controller: _note, maxLines: 2,
                decoration: const InputDecoration(hintText: 'e.g. I left at 6:30 PM')),
            if (_error != null) ...[const SizedBox(height: 14), InfoBanner(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _saving ? null : _send, child: const Text('Send to admin')),
        ],
      );
}
