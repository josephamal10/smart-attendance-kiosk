import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../widgets/clock_widget.dart';
import '../widgets/ui.dart';
import 'lock_screen.dart';
import 'face_register_screen.dart';

enum _Page { overview, attendance, employees }

extension on _Page {
  String get title => switch (this) {
        _Page.overview   => 'Overview',
        _Page.attendance => 'Attendance records',
        _Page.employees  => 'Employees',
      };
  IconData get icon => switch (this) {
        _Page.overview   => Icons.space_dashboard_outlined,
        _Page.attendance => Icons.event_note_outlined,
        _Page.employees  => Icons.groups_outlined,
      };
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  _Page _page = _Page.overview;
  bool _loading = true;

  List<AttendanceLog> _todayLogs = [];
  List<AttendanceLog> _allLogs = [];
  List<Employee> _employees = [];
  final Map<int, int> _faceCounts = {};
  final Map<int, Map<String, dynamic>> _monthStats = {};
  DateTimeRange? _range;

  static final _day = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getTodayAll(),
        ApiService.getAllAttendance(
          start: _range == null ? null : _day.format(_range!.start),
          end: _range == null ? null : _day.format(_range!.end),
        ),
        ApiService.getAllEmployees(),
        ApiService.getAttendancePercentage(),
      ]);
      final emps = results[2] as List<Employee>;
      final counts = await Future.wait(emps.map((e) => ApiService.getFaceCount(e.id)));
      if (!mounted) return;
      setState(() {
        _todayLogs = (results[0] as List<AttendanceLog>)
          ..sort((a, b) => (b.inTime ?? DateTime(0)).compareTo(a.inTime ?? DateTime(0)));
        _allLogs = (results[1] as List<AttendanceLog>)
          ..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            return byDate != 0 ? byDate : (b.inTime ?? DateTime(0)).compareTo(a.inTime ?? DateTime(0));
          });
        _employees = emps;
        _faceCounts
          ..clear()
          ..addAll({for (var i = 0; i < emps.length; i++) emps[i].id: (counts[i]['total'] as int?) ?? 0});
        _monthStats
          ..clear()
          ..addAll({for (final r in results[3]) r['employee_id'] as int: Map<String, dynamic>.from(r)});
      });
    } catch (e) {
      if (mounted) _toast('Could not load data: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? AppTheme.danger : AppTheme.textPrimary,
      content: Text(msg),
    ));
  }

  Future<void> _exportCSV() async {
    try {
      final path = await ApiService.downloadReport();
      if (mounted) _toast('Report saved to $path');
    } catch (e) {
      if (mounted) _toast('Export failed: $e', error: true);
    }
  }

  void _logout() {
    ApiService.clearSession();
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LockScreen()), (_) => false);
  }

  Future<void> _addEmployee() async {
    final created = await showDialog<String>(context: context, builder: (_) => const _AddEmployeeDialog());
    if (created != null && mounted) {
      _toast('$created was added. Register their face next.');
      _loadData();
    }
  }

  Future<void> _registerFace(Employee emp, {bool replace = false}) async {
    if (replace) {
      final ok = await _confirm(
        title: 'Re-register ${emp.name}?',
        message: 'Their ${_faceCounts[emp.id] ?? 0} current face photos will be deleted '
            'and replaced by a new set of 30.',
        action: 'Delete & re-register',
      );
      if (!ok) return;
      try {
        await ApiService.deleteFaceImages(emp.id);
      } catch (e) {
        if (mounted) _toast('Could not delete old photos: $e', error: true);
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FaceRegisterScreen(employeeId: emp.id, employeeName: emp.name)));
    _loadData();
  }

  Future<void> _deleteFaces(Employee emp) async {
    final ok = await _confirm(
      title: 'Delete face data for ${emp.name}?',
      message: "They won't be able to check in until their face is registered again.",
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await ApiService.deleteFaceImages(emp.id);
      if (mounted) _toast('Face data deleted for ${emp.name}.');
      _loadData();
    } catch (e) {
      if (mounted) _toast('Delete failed: $e', error: true);
    }
  }

  Future<bool> _confirm({required String title, required String message, required String action}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 380, child: Text(message, style: AppTheme.muted)),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      builder: (ctx, child) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640), child: child),
      ),
    );
    if (picked != null) {
      setState(() => _range = picked);
      _loadData();
    }
  }

  String _empName(int id) =>
      _employees.where((e) => e.id == id).map((e) => e.name).firstOrNull ?? 'Former employee';

  // ── Layout ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        _sidebar(),
        Expanded(
          child: Column(children: [
            _topBar(),
            Expanded(
              child: _loading && _employees.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: switch (_page) {
                            _Page.overview   => _overview(),
                            _Page.attendance => _attendance(),
                            _Page.employees  => _employeesPage(),
                          },
                        ),
                      ),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _sidebar() {
    final admin = ApiService.name ?? 'Administrator';
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: BrandMark(size: 34, subtitle: 'Admin console'),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text('MENU', style: AppTheme.overline),
        ),
        for (final p in _Page.values)
          _NavItem(
            icon: p.icon,
            label: p == _Page.attendance ? 'Attendance' : p.title,
            selected: _page == p,
            onTap: () => setState(() => _page = p),
          ),
        const Spacer(),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          InitialsAvatar(admin, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(admin, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Text('Administrator', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ]),
          ),
          IconButton(tooltip: 'Sign out', onPressed: _logout, icon: const Icon(Icons.logout, size: 20)),
        ]),
      ]),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_page.title, style: AppTheme.h1),
            const SizedBox(height: 4),
            Row(children: [
              Text(DateFormat('EEEE, d MMMM y').format(DateTime.now()), style: AppTheme.muted),
              Text('  ·  ', style: AppTheme.muted),
              const ClockWidget(large: false),
            ]),
          ]),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _loadData, icon: const Icon(Icons.refresh)),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _exportCSV,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Export CSV'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _addEmployee,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add employee'),
        ),
      ]),
    );
  }

  // ── Overview ─────────────────────────────────────────────

  Widget _overview() {
    final total = _employees.where((e) => e.isActive).length;
    final present = _todayLogs.length;
    final out = _todayLogs.where((l) => l.outTime != null).length;
    final notIn = (total - present).clamp(0, total);
    final noFace = _employees.where((e) => (_faceCounts[e.id] ?? 0) == 0).length;
    final pct = total == 0 ? 0 : (present * 100 / total).round();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: StatCard(label: 'Team members', value: '$total',
            icon: Icons.groups_outlined, tone: Tone.primary,
            caption: noFace == 0 ? 'All faces registered' : '$noFace without a registered face')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Present today', value: '$present',
            icon: Icons.how_to_reg_outlined, tone: Tone.success, caption: '$pct% of the team')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Checked out', value: '$out',
            icon: Icons.logout, tone: Tone.neutral, caption: '${present - out} still working')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Not checked in', value: '$notIn',
            icon: Icons.schedule_outlined, tone: notIn > 0 ? Tone.warning : Tone.neutral,
            caption: 'As of ${DateFormat('h:mm a').format(DateTime.now())}')),
      ])),
      const SizedBox(height: 24),
      _logTable(
        _todayLogs,
        header: _cardHeader("Today's activity", '${_todayLogs.length} check-ins'),
        showDate: false,
        empty: const EmptyState(icon: Icons.wb_sunny_outlined, title: 'No check-ins yet today',
            message: 'People appear here as soon as they scan in at the kiosk.'),
      ),
    ]);
  }

  Widget _cardHeader(String title, String subtitle, {Widget? trailing}) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.h3),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTheme.muted),
          ]),
        ),
        if (trailing != null) trailing,
      ]);

  Widget _logTable(List<AttendanceLog> logs,
      {required Widget header, required bool showDate, required Widget empty}) {
    final time = DateFormat('h:mm a');
    return DataCard(
      header: header,
      empty: empty,
      columns: [
        const Col('Employee', flex: 3),
        if (showDate) const Col('Date', flex: 2),
        const Col('Check in', flex: 2),
        const Col('Check out', flex: 2),
        const Col('Hours', flex: 2),
        const Col('Status', flex: 2),
      ],
      rows: [
        for (final l in logs)
          [
            PersonCell(_empName(l.employeeId)),
            if (showDate) Text(DateFormat('EEE, d MMM y').format(DateTime.parse(l.date)), style: AppTheme.body),
            Text(l.inTime == null ? '—' : time.format(l.inTime!), style: AppTheme.body),
            Text(l.outTime == null ? '—' : time.format(l.outTime!), style: AppTheme.body),
            Text(_hours(l), style: AppTheme.body.copyWith(fontFeatures: AppTheme.tabular)),
            l.outTime != null
                ? const StatusBadge('Completed', tone: Tone.success)
                : l.inTime != null
                    ? (showDate && l.date != _day.format(DateTime.now())
                        ? const StatusBadge('No check-out', tone: Tone.warning)
                        : const StatusBadge('Working', tone: Tone.primary))
                    : const StatusBadge('Absent', tone: Tone.danger),
          ],
      ],
    );
  }

  String _hours(AttendanceLog l) {
    if (l.inTime == null || l.outTime == null) return '—';
    final d = l.outTime!.difference(l.inTime!);
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }

  // ── Attendance records ───────────────────────────────────

  Widget _attendance() {
    final fmt = DateFormat('d MMM y');
    final rangeText = _range == null
        ? 'All dates'
        : '${fmt.format(_range!.start)} – ${fmt.format(_range!.end)}';
    return _logTable(
      _allLogs,
      showDate: true,
      header: _cardHeader('History', '${_allLogs.length} records · $rangeText',
          trailing: Row(children: [
            if (_range != null)
              TextButton(
                onPressed: () { setState(() => _range = null); _loadData(); },
                child: const Text('Clear'),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(rangeText),
            ),
          ])),
      empty: const EmptyState(icon: Icons.event_busy_outlined, title: 'No records',
          message: 'Try a different date range.'),
    );
  }

  // ── Employees ────────────────────────────────────────────

  Widget _employeesPage() => _EmployeesTable(
        employees: _employees,
        faceCounts: _faceCounts,
        monthStats: _monthStats,
        header: _cardHeader,
        onRegister: (e) => _registerFace(e),
        onReplace: (e) => _registerFace(e, replace: true),
        onDelete: _deleteFaces,
      );
}

// ── Sidebar item ─────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? AppTheme.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(icon, size: 20, color: selected ? AppTheme.primary : AppTheme.textSecondary),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary)),
              ]),
            ),
          ),
        ),
      );
}

// ── Employees table ──────────────────────────────────────────

class _EmployeesTable extends StatefulWidget {
  final List<Employee> employees;
  final Map<int, int> faceCounts;
  final Map<int, Map<String, dynamic>> monthStats;
  final Widget Function(String, String, {Widget? trailing}) header;
  final void Function(Employee) onRegister, onReplace, onDelete;
  const _EmployeesTable({
    required this.employees, required this.faceCounts, required this.monthStats,
    required this.header, required this.onRegister, required this.onReplace, required this.onDelete,
  });

  @override
  State<_EmployeesTable> createState() => _EmployeesTableState();
}

class _EmployeesTableState extends State<_EmployeesTable> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = widget.employees
        .where((e) => e.name.toLowerCase().contains(q) || e.username.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return DataCard(
      header: widget.header(
        'Team', '${widget.employees.length} people',
        trailing: SizedBox(
          width: 280,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search by name or username',
              prefixIcon: Icon(Icons.search, size: 20),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      empty: EmptyState(
        icon: Icons.person_search_outlined,
        title: widget.employees.isEmpty ? 'No employees yet' : 'No matches',
        message: widget.employees.isEmpty
            ? 'Use "Add employee" to create the first account.'
            : 'Nobody matches "$_query".',
      ),
      columns: const [
        Col('Employee', flex: 4),
        Col('Account', flex: 2),
        Col('This month', flex: 3),
        Col('Face', flex: 3),
        Col('', flex: 3, alignEnd: true),
      ],
      rows: [for (final e in list) _row(e)],
    );
  }

  List<Widget> _row(Employee e) {
    final faces = widget.faceCounts[e.id] ?? 0;
    final stats = widget.monthStats[e.id];
    final pct = (stats?['percentage'] as num?)?.toDouble();
    final tone = pct == null ? Tone.neutral : pct >= 75 ? Tone.success : pct >= 50 ? Tone.warning : Tone.danger;

    return [
      PersonCell(e.name, secondary: '@${e.username}'),
      StatusBadge(e.isActive ? 'Active' : 'Disabled', tone: e.isActive ? Tone.success : Tone.neutral),
      pct == null
          ? const Text('—', style: TextStyle(color: AppTheme.textMuted))
          : SizedBox(
              width: 170,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text('${pct.toStringAsFixed(0)}%', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: tone.fg)),
                  const SizedBox(width: 6),
                  Text('${stats!['attended_days']}/${stats['working_days']} days',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0), minHeight: 6,
                    color: tone.fg, backgroundColor: AppTheme.border,
                  ),
                ),
              ]),
            ),
      faces > 0
          ? StatusBadge('Registered · $faces photos', tone: Tone.success)
          : const StatusBadge('Not registered', tone: Tone.warning),
      faces == 0
          ? ElevatedButton.icon(
              onPressed: () => widget.onRegister(e),
              icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
              label: const Text('Register face'),
            )
          : Row(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton(onPressed: () => widget.onReplace(e), child: const Text('Re-register')),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                onSelected: (v) => v == 'add' ? widget.onRegister(e) : widget.onDelete(e),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: ListTile(
                      dense: true, contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_a_photo_outlined, size: 20), title: Text('Add more photos'))),
                  PopupMenuItem(value: 'delete', child: ListTile(
                      dense: true, contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                      title: Text('Delete face data', style: TextStyle(color: AppTheme.danger)))),
                ],
              ),
            ]),
    ];
  }
}

// ── Add employee dialog ──────────────────────────────────────

class _AddEmployeeDialog extends StatefulWidget {
  const _AddEmployeeDialog();
  @override
  State<_AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<_AddEmployeeDialog> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String _role = 'user';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _user.dispose(); _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.registerEmployee(_name.text.trim(), _user.text.trim(), _pass.text, _role);
      if (mounted) Navigator.pop(context, _name.text.trim());
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 422
          ? 'Please fill every field. Usernames need 2+ characters and passwords 6+.'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {bool secret = false, String? hint, IconData? icon}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.label),
        const SizedBox(height: 6),
        TextField(
          controller: c, obscureText: secret,
          decoration: InputDecoration(hintText: hint, prefixIcon: icon == null ? null : Icon(icon, size: 20)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Add employee'),
        const SizedBox(height: 4),
        Text('They can sign in at the kiosk once their face is registered.', style: AppTheme.muted),
      ]),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          _field('Full name', _name, hint: 'e.g. Priya Raman', icon: Icons.badge_outlined),
          const SizedBox(height: 16),
          _field('Username', _user, hint: 'e.g. priya', icon: Icons.alternate_email),
          const SizedBox(height: 16),
          _field('Password', _pass, secret: true, hint: 'At least 6 characters', icon: Icons.lock_outline),
          const SizedBox(height: 16),
          Text('Role', style: AppTheme.label),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'user', label: Text('Employee'), icon: Icon(Icons.person_outline)),
              ButtonSegment(value: 'admin', label: Text('Admin'), icon: Icon(Icons.admin_panel_settings_outlined)),
            ],
            selected: {_role},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          if (_error != null) ...[const SizedBox(height: 16), InfoBanner(_error!)],
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add employee'),
        ),
      ],
    );
  }
}
