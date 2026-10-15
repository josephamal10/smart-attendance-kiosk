import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../widgets/clock_widget.dart';
import '../widgets/ui.dart';
import 'face_register_screen.dart';
import 'admin/analytics_page.dart';
import 'admin/attendance_edit_dialog.dart';
import 'admin/audit_page.dart';
import 'admin/holidays_page.dart';
import 'admin/requests_page.dart';
import 'admin/settings_page.dart';
import 'admin/register_view.dart';
import 'admin/employee_profile.dart';
import '../theme/appearance.dart';

enum _Page { overview, attendance, employees, requests, holidays, analytics, audit, settings }

extension on _Page {
  String get title => switch (this) {
        _Page.overview   => 'Overview',
        _Page.attendance => 'Attendance records',
        _Page.employees  => 'Employees',
        _Page.requests   => 'Requests',
        _Page.holidays   => 'Holidays',
        _Page.analytics  => 'Analytics',
        _Page.audit      => 'Audit log',
        _Page.settings   => 'Settings',
      };
  String get navLabel => this == _Page.attendance ? 'Attendance' : title;
  IconData get icon => switch (this) {
        _Page.overview   => Icons.space_dashboard_outlined,
        _Page.attendance => Icons.event_note_outlined,
        _Page.employees  => Icons.groups_outlined,
        _Page.requests   => Icons.inbox_outlined,
        _Page.holidays   => Icons.celebration_outlined,
        _Page.analytics  => Icons.insights_outlined,
        _Page.audit      => Icons.history,
        _Page.settings   => Icons.settings_outlined,
      };
}

/// Sidebar groups
const _navGroups = [
  ('WORKSPACE', [_Page.overview, _Page.attendance, _Page.employees]),
  ('MANAGE', [_Page.requests, _Page.holidays]),
  ('INSIGHTS', [_Page.analytics, _Page.audit]),
];

/// Employees without a category yet (added before categories existed).
const _noTeam = 'No team';

class AdminDashboard extends StatefulWidget {
  /// Optional deep link, e.g. 'analytics' or 'attendance:register' (used by the screenshot tool)
  final String? initialPage;
  final int? initialProfileId;
  const AdminDashboard({super.key, this.initialPage, this.initialProfileId});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  _Page _page = _Page.overview;
  int? _profileId;                 // set when looking at one employee's profile
  String _attendanceView = 'daily'; // daily log or monthly register
  Timer? _live;                    // quiet auto-refresh so new check-ins appear by themselves
  DateTime? _updatedAt;
  int _profileRev = 0;             // bumped after edits so an open profile reloads
  bool _loading = true;

  List<AttendanceLog> _todayLogs = [];
  List<AttendanceLog> _allLogs = [];
  List<Employee> _employees = [];
  List<String> _categories = [];
  final Map<int, int> _faceCounts = {};
  final Map<int, Map<String, dynamic>> _monthStats = {};
  DateTimeRange? _range;
  String? _team; // team filter on the Attendance page (null = everyone)
  int _pending = 0; // leave + correction requests waiting for a decision
  int _onLeaveToday = 0;

  static final _day = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    final link = widget.initialPage?.split(':');
    if (link != null) {
      _page = _Page.values.where((p) => p.name == link.first).firstOrNull ?? _Page.overview;
      if (link.length > 1) _attendanceView = link[1];
    }
    if (widget.initialProfileId != null) {
      _page = _Page.employees;
      _profileId = widget.initialProfileId;
    }
    _loadData();
    _live = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  void _go(_Page p) => setState(() { _page = p; _profileId = null; });

  void _openProfile(int employeeId) => setState(() { _page = _Page.employees; _profileId = employeeId; });

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getTodayAll(),
        ApiService.getAllAttendance(
          start: _range == null ? null : _day.format(_range!.start),
          end: _range == null ? null : _day.format(_range!.end),
        ),
        ApiService.getAllEmployees(),
        ApiService.getAttendancePercentage(),
        ApiService.getLeave(status: 'pending'),
        ApiService.getCorrections(status: 'pending'),
        ApiService.getLeave(status: 'approved'),
        if (_categories.isEmpty) ApiService.getCategories(),
      ]);
      final emps = results[2] as List<Employee>;
      final counts = await Future.wait(emps.map((e) => ApiService.getFaceCount(e.id)));
      if (!mounted) return;
      setState(() {
        _updatedAt = DateTime.now();
        if (results.length > 7) _categories = results[7] as List<String>;
        _pending = results[4].length + results[5].length;
        final today = DateTime.now();
        final day = DateTime(today.year, today.month, today.day);
        _onLeaveToday = (results[6] as List<LeaveRequest>)
            .where((l) => !l.startDate.isAfter(day) && !l.endDate.isBefore(day))
            .map((l) => l.employeeId).toSet().length;
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
      // A failed background refresh stays quiet; the next one will try again
      if (mounted && !silent) _toast('Could not load data: $e', error: true);
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
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

  /// Back to the sign-in screen, which then returns to the kiosk.
  void _logout() {
    ApiService.clearSession();
    Navigator.of(context).pop();
  }

  Future<void> _addEmployee() async {
    final created = await showDialog<Employee>(
        context: context, builder: (_) => _EmployeeDialog(categories: _categories));
    if (created == null || !mounted) return;
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${created.name} was added to ${created.category}. Register their face next.'),
      action: SnackBarAction(label: 'Register face', onPressed: () => _registerFace(created)),
      duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _editEmployee(Employee emp) async {
    final saved = await showDialog<Employee>(
        context: context, builder: (_) => _EmployeeDialog(categories: _categories, employee: emp));
    if (saved != null && mounted) {
      _toast('Saved changes for ${saved.name}.');
      setState(() => _profileRev++);
      _loadData();
    }
  }

  Future<void> _editLog(AttendanceLog log) async {
    final saved = await showDialog<AttendanceLog>(context: context,
        builder: (_) => AttendanceEditDialog(log: log, employees: _employees));
    if (saved != null && mounted) {
      _toast('Record corrected. The change is in the audit log.');
      _loadData();
    }
  }

  Future<void> _addLog() async {
    final saved = await showDialog<AttendanceLog>(context: context,
        builder: (_) => AttendanceEditDialog(employees: _employees));
    if (saved != null && mounted) {
      _toast('Record added.');
      _loadData();
    }
  }

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _ChangePasswordDialog());
    if (ok == true && mounted) _toast('Password changed. Use it next time you sign in.');
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
    if (mounted) setState(() => _profileRev++);
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

  Employee? _emp(int id) => _employees.where((e) => e.id == id).firstOrNull;
  String _teamOf(int employeeId) => _emp(employeeId)?.category ?? _noTeam;

  /// Teams to show: the official categories, plus "No team" if anyone still lacks one.
  List<String> get _teams => [
        ..._categories,
        if (_employees.any((e) => e.category == null)) _noTeam,
      ];

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
                            _Page.employees  => _profileId == null
                                ? _employeesPage()
                                : EmployeeProfileView(
                                    key: ValueKey(_profileId),
                                    employeeId: _profileId!,
                                    revision: _profileRev,
                                    onBack: () => setState(() => _profileId = null),
                                    onEdit: _editEmployee,
                                    onRegisterFace: (e, {bool replace = false}) => _registerFace(e, replace: replace),
                                  ),
                            _Page.requests   => RequestsPage(employees: _employees, onChanged: _loadData),
                            _Page.holidays   => HolidaysPage(onChanged: _loadData),
                            _Page.analytics  => const AnalyticsPage(),
                            _Page.audit      => AuditPage(employees: _employees),
                            _Page.settings   => const SettingsPage(),
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
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: BrandMark(size: 34, subtitle: 'Admin console'),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView(children: [
            for (final (group, pages) in _navGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 8),
                child: Text(group, style: AppTheme.overline),
              ),
              for (final p in pages)
                _NavItem(
                  icon: p.icon,
                  label: p.navLabel,
                  selected: _page == p,
                  badge: p == _Page.requests && _pending > 0 ? _pending : null,
                  onTap: () => _go(p),
                ),
            ],
          ]),
        ),
        _NavItem(
          icon: _Page.settings.icon,
          label: 'Settings',
          selected: _page == _Page.settings,
          onTap: () => setState(() => _page = _Page.settings),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: Appearance.dark,
          builder: (_, dark, __) => _NavItem(
            icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            label: dark ? 'Light mode' : 'Dark mode',
            selected: false,
            onTap: () => Appearance.setDark(!dark),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          InitialsAvatar(admin, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(admin, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('Administrator', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) => v == 'password' ? _changePassword() : _logout(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'password', child: ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.key_outlined, size: 20), title: Text('Change password'))),
              PopupMenuItem(value: 'logout', child: ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout, size: 20), title: Text('Sign out'))),
            ],
          ),
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
            Text(_profileId != null && _page == _Page.employees ? 'Employee profile' : _page.title,
                style: AppTheme.h1),
            const SizedBox(height: 4),
            Row(children: [
              Text(DateFormat('EEEE, d MMMM y').format(DateTime.now()), style: AppTheme.muted),
              Text('  ·  ', style: AppTheme.muted),
              const ClockWidget(large: false),
              if (_updatedAt != null) ...[
                const SizedBox(width: 14),
                Tooltip(
                  message: 'Refreshes automatically every 30 seconds',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Live · updated ${DateFormat('h:mm:ss a').format(_updatedAt!)}', style: AppTheme.muted),
                  ]),
                ),
              ],
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
        if (_page == _Page.attendance)
          ElevatedButton.icon(
            onPressed: _employees.isEmpty ? null : _addLog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add record'),
          )
        else
          ElevatedButton.icon(
            onPressed: _categories.isEmpty ? null : _addEmployee,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add employee'),
          ),
      ]),
    );
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

  /// "All · HR · Developer ..." filter chips.
  Widget _teamChips(String? selected, ValueChanged<String?> onSelect) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in [null, ..._teams])
            ChoiceChip(
              label: Text(t ?? 'All teams'),
              selected: selected == t,
              showCheckmark: false,
              onSelected: (_) => onSelect(t),
              labelStyle: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: selected == t ? AppTheme.primary : AppTheme.textSecondary,
              ),
              backgroundColor: AppTheme.surface,
              selectedColor: AppTheme.primarySoft,
              side: BorderSide(color: selected == t ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
        ],
      );

  // ── Overview ─────────────────────────────────────────────

  Widget _overview() {
    final active = _employees.where((e) => e.isActive).toList();
    final total = active.length;
    final present = _todayLogs.length;
    final out = _todayLogs.where((l) => l.outTime != null).length;
    final late = _todayLogs.where((l) => l.isLate).length;
    final notIn = (total - present - _onLeaveToday).clamp(0, total);
    final noFace = active.where((e) => (_faceCounts[e.id] ?? 0) == 0).length;
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
        Expanded(child: StatCard(label: 'Late today', value: '$late',
            icon: Icons.running_with_errors_outlined, tone: late > 0 ? Tone.warning : Tone.neutral,
            caption: '$out checked out · ${present - out} still working')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Not checked in', value: '$notIn',
            icon: Icons.schedule_outlined, tone: notIn > 0 ? Tone.danger : Tone.neutral,
            caption: _onLeaveToday > 0
                ? '$_onLeaveToday on leave · as of ${DateFormat('h:mm a').format(DateTime.now())}'
                : 'As of ${DateFormat('h:mm a').format(DateTime.now())}')),
      ])),
      if (_pending > 0) ...[
        const SizedBox(height: AppTheme.gap),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            onTap: () => setState(() => _page = _Page.requests),
            child: InfoBanner('$_pending request${_pending == 1 ? '' : 's'} waiting for you — '
                'leave or attendance corrections. Click to review.', tone: Tone.primary),
          ),
        ),
      ],
      const SizedBox(height: 24),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: _logTable(
            _todayLogs,
            header: _cardHeader("Today's activity", '${_todayLogs.length} check-ins'),
            showDate: false,
            empty: const EmptyState(icon: Icons.wb_sunny_outlined, title: 'No check-ins yet today',
                message: 'People appear here as soon as they scan in at the kiosk.'),
          ),
        ),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: _byTeamCard(active)),
      ]),
    ]);
  }

  Widget _byTeamCard(List<Employee> active) {
    final presentIds = _todayLogs.map((l) => l.employeeId).toSet();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHeader('By team', 'Present today'),
        const SizedBox(height: 18),
        for (final team in _teams) ...[
          Builder(builder: (_) {
            final members = active.where((e) => (e.category ?? _noTeam) == team).toList();
            final here = members.where((e) => presentIds.contains(e.id)).length;
            final frac = members.isEmpty ? 0.0 : here / members.length;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(team, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                Text(members.isEmpty ? '—' : '$here / ${members.length}',
                    style: AppTheme.muted.copyWith(fontFeatures: AppTheme.tabular)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: frac, minHeight: 6,
                    color: AppTheme.primary, backgroundColor: AppTheme.border),
              ),
            ]);
          }),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }

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
        if (showDate) const Col('Hours', flex: 2),
        const Col('Status', flex: 3),
        const Col('', flex: 1, alignEnd: true),
      ],
      rows: [
        for (final l in logs)
          [
            PersonCell(_emp(l.employeeId)?.name ?? 'Former employee', secondary: _teamOf(l.employeeId)),
            if (showDate) Text(DateFormat('EEE, d MMM y').format(DateTime.parse(l.date)), style: AppTheme.body),
            Text(l.inTime == null ? '—' : time.format(l.inTime!), style: AppTheme.body),
            Text(l.outTime == null ? '—' : time.format(l.outTime!), style: AppTheme.body),
            if (showDate) Text(_hours(l), style: AppTheme.body.copyWith(fontFeatures: AppTheme.tabular)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (l.outTime == null && l.inTime != null && l.date == _day.format(DateTime.now()))
                const StatusBadge('Working', tone: Tone.primary)
              else if (l.outTime == null && l.inTime != null)
                const StatusBadge('No check-out', tone: Tone.warning),
              FlagBadges(flags: l.flags, lateMinutes: l.lateMinutes, earlyMinutes: l.earlyMinutes,
                  whenClean: l.outTime != null ? const StatusBadge('Completed', tone: Tone.success) : null),
            ]),
            IconButton(tooltip: 'Correct this record', onPressed: () => _editLog(l),
                icon: const Icon(Icons.edit_outlined, size: 18)),
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

  Widget _attendance() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'daily', label: Text('Daily log'), icon: Icon(Icons.view_list_outlined)),
              ButtonSegment(value: 'register', label: Text('Monthly register'), icon: Icon(Icons.grid_on_outlined)),
            ],
            selected: {_attendanceView},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _attendanceView = s.first),
          ),
        ),
        const SizedBox(height: AppTheme.gap),
        _attendanceView == 'register' ? RegisterView(onOpenEmployee: _openProfile) : _dailyLog(),
      ]);

  Widget _dailyLog() {
    final fmt = DateFormat('d MMM y');
    final rangeText = _range == null
        ? 'All dates'
        : '${fmt.format(_range!.start)} – ${fmt.format(_range!.end)}';
    final logs = _team == null ? _allLogs : _allLogs.where((l) => _teamOf(l.employeeId) == _team).toList();
    return _logTable(
      logs,
      showDate: true,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardHeader('History', '${logs.length} records · $rangeText',
            trailing: Row(children: [
              if (_range != null)
                TextButton(
                  onPressed: () { setState(() => _range = null); _loadData(); },
                  child: const Text('Clear dates'),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(rangeText),
              ),
            ])),
        const SizedBox(height: 14),
        _teamChips(_team, (t) => setState(() => _team = t)),
      ]),
      empty: const EmptyState(icon: Icons.event_busy_outlined, title: 'No records',
          message: 'Try a different date range or team.'),
    );
  }

  // ── Employees ────────────────────────────────────────────

  Widget _employeesPage() => _EmployeesTable(
        employees: _employees,
        faceCounts: _faceCounts,
        monthStats: _monthStats,
        header: _cardHeader,
        teamChips: _teamChips,
        onRegister: (e) => _registerFace(e),
        onReplace: (e) => _registerFace(e, replace: true),
        onDelete: _deleteFaces,
        onEdit: _editEmployee,
        onOpen: (e) => _openProfile(e.id),
      );
}

// ── Sidebar item ─────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.badge});

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
                Expanded(child: Text(label, style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary))),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(999)),
                    child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
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
  final Widget Function(String?, ValueChanged<String?>) teamChips;
  final void Function(Employee) onRegister, onReplace, onDelete, onEdit, onOpen;
  const _EmployeesTable({
    required this.employees, required this.faceCounts, required this.monthStats,
    required this.header, required this.teamChips, required this.onRegister,
    required this.onReplace, required this.onDelete, required this.onEdit, required this.onOpen,
  });

  @override
  State<_EmployeesTable> createState() => _EmployeesTableState();
}

class _EmployeesTableState extends State<_EmployeesTable> {
  String _query = '';
  String? _team;

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = widget.employees
        .where((e) => _team == null || (e.category ?? _noTeam) == _team)
        .where((e) => e.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return DataCard(
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        widget.header(
          'Team', '${widget.employees.length} people',
          trailing: SizedBox(
            width: 280,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        widget.teamChips(_team, (t) => setState(() => _team = t)),
      ]),
      empty: EmptyState(
        icon: Icons.person_search_outlined,
        title: widget.employees.isEmpty ? 'No employees yet' : 'No matches',
        message: widget.employees.isEmpty
            ? 'Use "Add employee" to add the first person.'
            : 'Nobody matches this search or team.',
      ),
      columns: const [
        Col('Employee', flex: 4),
        Col('Team', flex: 2),
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
      InkWell(
        onTap: () => widget.onOpen(e),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: PersonCell(e.name, secondary: e.isActive ? 'View profile' : 'Disabled — cannot check in'),
        ),
      ),
      e.category == null
          ? const StatusBadge('Not set', tone: Tone.warning)
          : StatusBadge(e.category!, tone: Tone.neutral, dot: false),
      pct == null
          ? Text('—', style: TextStyle(color: AppTheme.textMuted))
          : SizedBox(
              width: 170,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text('${pct.toStringAsFixed(0)}%', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: tone.fg)),
                  const SizedBox(width: 6),
                  Text('${stats!['attended_days']}/${stats['working_days']} days',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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
      Row(mainAxisSize: MainAxisSize.min, children: [
        faces == 0
            ? ElevatedButton.icon(
                onPressed: () => widget.onRegister(e),
                icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
                label: const Text('Register face'),
              )
            : OutlinedButton(onPressed: () => widget.onReplace(e), child: const Text('Re-register')),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(Icons.more_vert, color: AppTheme.textSecondary),
          onSelected: (v) => switch (v) {
            'profile' => widget.onOpen(e),
            'edit' => widget.onEdit(e),
            'add' => widget.onRegister(e),
            _ => widget.onDelete(e),
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'profile', child: ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.badge_outlined, size: 20), title: Text('View profile'))),
            const PopupMenuItem(value: 'edit', child: ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined, size: 20), title: Text('Edit details'))),
            if (faces > 0) ...[
              const PopupMenuItem(value: 'add', child: ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_a_photo_outlined, size: 20), title: Text('Add more photos'))),
              PopupMenuItem(value: 'delete', child: ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                  title: Text('Delete face data', style: TextStyle(color: AppTheme.danger)))),
            ],
          ],
        ),
      ]),
    ];
  }
}

// ── Add / edit employee dialog ───────────────────────────────

class _EmployeeDialog extends StatefulWidget {
  final List<String> categories;
  final Employee? employee; // null = add a new one
  const _EmployeeDialog({required this.categories, this.employee});
  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final _name = TextEditingController(text: widget.employee?.name);
  late String? _category = widget.employee?.category;
  late bool _active = widget.employee?.isActive ?? true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.employee != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _category == null) {
      setState(() => _error = 'Enter a name and choose a team.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final saved = _editing
          ? await ApiService.updateEmployee(widget.employee!.id, name: name, category: _category, isActive: _active)
          : await ApiService.createEmployee(name, _category!);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _icons = {
    'HR': Icons.diversity_3_outlined,
    'Project Manager': Icons.assignment_ind_outlined,
    'Admin': Icons.business_center_outlined,
    'Developer': Icons.code,
    'Tester': Icons.bug_report_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_editing ? 'Edit employee' : 'Add employee'),
        const SizedBox(height: 4),
        Text(_editing
            ? 'Change their name, team or whether they can check in.'
            : 'No password needed — they check in with their face once it is registered.',
            style: AppTheme.muted),
      ]),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Text('Full name', style: AppTheme.label),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            autofocus: !_editing,
            decoration: const InputDecoration(
                hintText: 'e.g. Priya Raman', prefixIcon: Icon(Icons.badge_outlined, size: 20)),
          ),
          const SizedBox(height: 20),
          Text('Team', style: AppTheme.label),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in widget.categories)
              ChoiceChip(
                avatar: Icon(_icons[c] ?? Icons.work_outline, size: 18,
                    color: _category == c ? AppTheme.primary : AppTheme.textSecondary),
                label: Text(c),
                selected: _category == c,
                showCheckmark: false,
                onSelected: (_) => setState(() => _category = c),
                labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: _category == c ? AppTheme.primary : AppTheme.textPrimary),
                backgroundColor: AppTheme.surface,
                selectedColor: AppTheme.primarySoft,
                side: BorderSide(color: _category == c ? AppTheme.primary : AppTheme.borderStrong),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
          ]),
          if (_editing) ...[
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Can check in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(_active
                  ? 'Recognised at the kiosk'
                  : 'Disabled — the kiosk will not recognise them (history is kept)',
                  style: AppTheme.muted),
            ),
          ],
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
              : Text(_editing ? 'Save changes' : 'Add employee'),
        ),
      ],
    );
  }
}

// ── Change password dialog ───────────────────────────────────

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose(); _next.dispose(); _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.isEmpty) {
      setState(() => _error = 'Enter a new password.');
      return;
    }
    if (_next.text != _repeat.text) {
      setState(() => _error = "The new passwords don't match.");
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.changePassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {bool autofocus = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.label),
        const SizedBox(height: 6),
        TextField(controller: c, obscureText: true, autofocus: autofocus,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline, size: 20))),
      ]);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field('Current password', _current, autofocus: true),
          const SizedBox(height: 16),
          _field('New password', _next),
          const SizedBox(height: 16),
          _field('Repeat new password', _repeat),
          if (_error != null) ...[const SizedBox(height: 16), InfoBanner(_error!)],
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Change password')),
      ],
    );
  }
}
