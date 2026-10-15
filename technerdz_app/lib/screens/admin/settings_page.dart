import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/appearance.dart';
import '../../widgets/ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? _s;       // as last saved
  Map<String, dynamic> _edit = {}; // being edited
  bool _saving = false;
  bool _testing = false;
  bool _backingUp = false;
  Map<String, dynamic>? _backups;
  String? _error;
  final _company = TextEditingController();
  final _newEmail = TextEditingController();

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _company.dispose();
    _newEmail.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    try {
      final b = await ApiService.getBackups();
      if (mounted) setState(() => _backups = b);
    } catch (_) {}
  }

  Future<void> _backupNow() async {
    setState(() => _backingUp = true);
    try {
      final msg = await ApiService.backupNow();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _loadBackups();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _load() async {
    _loadBackups();
    try {
      final s = await ApiService.getSettings();
      if (!mounted) return;
      setState(() {
        _s = s;
        _edit = Map<String, dynamic>.from(s);
        _company.text = s['company_name'];
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load settings: $e');
    }
  }

  bool get _dirty => _s != null && _edit.entries.any((e) => e.key != 'smtp_configured'
      && e.value.toString() != _s![e.key].toString());

  void _set(String key, dynamic value) => setState(() => _edit[key] = value);

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final saved = await ApiService.saveSettings({..._edit, 'company_name': _company.text.trim()});
      if (!mounted) return;
      setState(() { _s = saved; _edit = Map<String, dynamic>.from(saved); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 422 ? 'Some values are not valid: ${e.message}' : e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testEmail() async {
    setState(() => _testing = true);
    try {
      final msg = await ApiService.sendTestEmail();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  TimeOfDay _tod(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _timeButton(String key) => OutlinedButton.icon(
        onPressed: () async {
          final t = await showTimePicker(context: context, initialTime: _tod(_edit[key]));
          if (t != null) _set(key, _hhmm(t));
        },
        icon: const Icon(Icons.schedule, size: 18),
        label: Text(_tod(_edit[key]).format(context)),
      );

  Widget _stepper(String key, {required int step, required num min, required num max, String suffix = ''}) {
    final v = _edit[key] as num;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(onPressed: v - step < min ? null : () => _set(key, v - step),
          icon: const Icon(Icons.remove, size: 18)),
      SizedBox(
        width: 84,
        child: Text('${v is double && v == v.roundToDouble() ? v.toInt() : v}$suffix', textAlign: TextAlign.center,
            style: AppTheme.h3.copyWith(fontFeatures: AppTheme.tabular)),
      ),
      IconButton.outlined(onPressed: v + step > max ? null : () => _set(key, v + step),
          icon: const Icon(Icons.add, size: 18)),
    ]);
  }

  Widget _row(String title, String help, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(help, style: AppTheme.muted),
          ])),
          const SizedBox(width: 24),
          control,
        ]),
      );

  Widget _section(String title, IconData icon, List<Widget> rows) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 10),
            Text(title, style: AppTheme.h3),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(),
            rows[i],
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_s == null) {
      return _error != null ? InfoBanner(_error!) : const Center(child: CircularProgressIndicator());
    }
    final weekend = (_edit['weekend_days'] as List).cast<int>();
    final emails = (_edit['hr_emails'] as List).cast<String>();
    final smtp = _s!['smtp_configured'] == true;

    final readOnly = !ApiService.canEdit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (readOnly) ...[
        const InfoBanner('You can see the settings but not change them. Ask a super admin.', tone: Tone.primary),
        const SizedBox(height: AppTheme.gap),
      ],
      AbsorbPointer(absorbing: readOnly, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('Work hours & rules', Icons.schedule_outlined, [
        _row('Office hours', 'Used to mark late arrivals and early leavers.',
            Row(mainAxisSize: MainAxisSize.min, children: [
              _timeButton('work_start'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('to', style: AppTheme.muted)),
              _timeButton('work_end'),
            ])),
        _row('Grace period', 'Check-ins within this many minutes of the start time still count as on time.',
            _stepper('grace_minutes', step: 5, min: 0, max: 120, suffix: ' min')),
        _row('Half day', 'Days shorter than this are marked as a half day.',
            _stepper('half_day_hours', step: 1, min: 1, max: 8, suffix: ' h')),
        _row('Weekly days off', 'Not counted as working days, so nobody is absent on them.',
            Wrap(spacing: 6, children: [
              for (var d = 0; d < 7; d++)
                FilterChip(
                  label: Text(_days[d]),
                  selected: weekend.contains(d),
                  showCheckmark: false,
                  selectedColor: AppTheme.primarySoft,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600,
                      color: weekend.contains(d) ? AppTheme.primary : AppTheme.textSecondary),
                  side: BorderSide(color: weekend.contains(d) ? AppTheme.primary : AppTheme.border),
                  onSelected: (on) => _set('weekend_days', on ? [...weekend, d] : weekend.where((x) => x != d).toList()),
                ),
            ])),
        _row('Check-out gap', 'A second scan sooner than this after check-in is ignored, not a check-out.',
            _stepper('min_checkout_minutes', step: 5, min: 0, max: 120, suffix: ' min')),
        _row('Auto check-out', 'Anyone who forgets to check out is checked out at their shift end time and flagged.',
            const StatusBadge('Always on', tone: Tone.success)),
      ]),
      const SizedBox(height: AppTheme.gap),
      _section('Team shifts', Icons.groups_outlined, [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Teams without their own shift use the office hours above. Late, early leave, '
              'overtime and auto check-out all follow the team\'s shift.', style: AppTheme.muted),
        ),
        for (final team in _teams) _shiftRow(team),
      ]),
      const SizedBox(height: AppTheme.gap),
      _section('Leave allowance', Icons.beach_access_outlined, [
        _allowanceRow('casual', 'Casual leave', 'Days per year. Shown to employees as their leave balance.'),
        _allowanceRow('sick', 'Sick leave', 'Days per year.'),
        _allowanceRow('other', 'Other leave', 'Days per year. Leave at 0 to hide it from the balance.'),
      ]),
      const SizedBox(height: AppTheme.gap),
      _section('Daily email to HR', Icons.mail_outline, [
        if (!smtp)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: InfoBanner(
              'Email sending is not set up yet. Add your Gmail address and App Password as SMTP_USER and '
              'SMTP_PASSWORD in the server\'s .env file, then restart it. Until then, summaries are saved as '
              'files in reports/emails.', tone: Tone.warning),
          ),
        _row('Send daily summary', 'Present, late, on leave and absent, with each person\'s times.',
            Switch(value: _edit['email_enabled'] == true, onChanged: (v) => _set('email_enabled', v))),
        _row('Send at', 'Sent once a day, after this time.', _timeButton('email_time')),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recipients', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in emails)
                InputChip(label: Text(e), onDeleted: () => _set('hr_emails', emails.where((x) => x != e).toList())),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _newEmail,
                  decoration: const InputDecoration(hintText: 'Add email and press Enter',
                      prefixIcon: Icon(Icons.alternate_email, size: 18), contentPadding: EdgeInsets.symmetric(vertical: 10)),
                  onSubmitted: (v) {
                    final x = v.trim();
                    if (x.contains('@') && !emails.contains(x)) _set('hr_emails', [...emails, x]);
                    _newEmail.clear();
                  },
                ),
              ),
            ]),
          ]),
        ),
        _row('Try it now', 'Sends (or saves) today\'s summary immediately. Save your changes first.',
            OutlinedButton.icon(
              onPressed: _testing || _dirty ? null : _testEmail,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 18),
              label: const Text('Send test'),
            )),
      ]),
      const SizedBox(height: AppTheme.gap),
      _section('Backups', Icons.backup_outlined, [
        _row('Automatic backups',
            _backups == null
                ? 'Loading...'
                : _backups!['supported'] == true
                    ? 'A copy of the database is saved once a day. The newest ${_backups!['keep']} are kept in '
                      'the server\'s "${_backups!['folder']}" folder.'
                    : 'Only available with the built-in SQLite database. Back up your MySQL server separately.',
            OutlinedButton.icon(
              onPressed: _backingUp || _backups?['supported'] != true ? null : _backupNow,
              icon: _backingUp
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_alt, size: 18),
              label: const Text('Back up now'),
            )),
        if (_backups != null && (_backups!['backups'] as List).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              for (final b in (_backups!['backups'] as List).take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(Icons.description_outlined, size: 18, color: AppTheme.textMuted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(b['file'], style: AppTheme.body)),
                    Text('${b['size_kb']} KB', style: AppTheme.muted),
                    const SizedBox(width: 16),
                    Text(DateFormat('d MMM, h:mm a').format(DateTime.parse(b['created'])), style: AppTheme.muted),
                  ]),
                ),
            ]),
          ),
      ]),
      const SizedBox(height: AppTheme.gap),
      _section('General', Icons.tune, [
        _row('Company name', 'Shown in emails.',
            SizedBox(width: 280, child: TextField(controller: _company, onChanged: (_) => setState(() {})))),
        _row('Dark mode', 'Easier on the eyes in dim rooms. Applies to this computer.',
            ValueListenableBuilder<bool>(
              valueListenable: Appearance.dark,
              builder: (_, dark, __) => Switch(value: dark, onChanged: Appearance.setDark),
            )),
      ]),
      ])),
      const SizedBox(height: 20),
      if (_error != null) ...[InfoBanner(_error!), const SizedBox(height: 12)],
      if (!readOnly) Row(children: [
        if (_dirty) Text('You have unsaved changes', style: AppTheme.muted.copyWith(color: AppTheme.warning)),
        const Spacer(),
        OutlinedButton(
          onPressed: _dirty ? () => setState(() {
            _edit = Map<String, dynamic>.from(_s!);
            _company.text = _s!['company_name'];
          }) : null,
          child: const Text('Discard'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: (_dirty || _company.text.trim() != _s!['company_name']) && !_saving ? _save : null,
          child: const Text('Save settings'),
        ),
      ]),
    ]);
  }

  // ── Team shifts & leave allowance ──────────────────────────
  static const _teams = ['HR', 'Project Manager', 'Admin', 'Developer', 'Tester'];

  Map<String, dynamic> get _shifts => Map<String, dynamic>.from(_edit['team_shifts'] ?? {});

  Widget _shiftRow(String team) {
    final shift = _shifts[team] as Map?;
    Widget pick(String which) => OutlinedButton(
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: _tod(shift[which]));
            if (t == null) return;
            _set('team_shifts', {..._shifts, team: {...Map<String, dynamic>.from(shift), which: _hhmm(t)}});
          },
          child: Text(_tod(shift![which]).format(context)),
        );
    return _row(team, shift == null ? 'Office hours (${_edit['work_start']}–${_edit['work_end']})' : 'Own shift',
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (shift != null) ...[
            pick('start'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('to', style: AppTheme.muted)),
            pick('end'),
            const SizedBox(width: 12),
          ],
          Switch(
            value: shift != null,
            onChanged: (on) => _set('team_shifts', on
                ? {..._shifts, team: {'start': _edit['work_start'], 'end': _edit['work_end']}}
                : (_shifts..remove(team))),
          ),
        ]));
  }

  Widget _allowanceRow(String kind, String title, String help) {
    final all = Map<String, dynamic>.from(_edit['leave_allowance'] ?? {});
    final v = (all[kind] as num?)?.toInt() ?? 0;
    return _row(title, help, Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(onPressed: v <= 0 ? null : () => _set('leave_allowance', {...all, kind: v - 1}),
          icon: const Icon(Icons.remove, size: 18)),
      SizedBox(width: 84, child: Text('$v days', textAlign: TextAlign.center,
          style: AppTheme.h3.copyWith(fontFeatures: AppTheme.tabular))),
      IconButton.outlined(onPressed: v >= 60 ? null : () => _set('leave_allowance', {...all, kind: v + 1}),
          icon: const Icon(Icons.add, size: 18)),
    ]));
  }
}
