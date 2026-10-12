import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../widgets/clock_widget.dart';
import 'lock_screen.dart';
import 'face_register_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final _pages = ['Today', 'All Records', 'Employees'];

  List<AttendanceLog> _todayLogs = [];
  List<AttendanceLog> _allLogs   = [];
  List<Employee>      _employees = [];
  bool _loading = true;

  // Date filter
  String? _startDate;
  String? _endDate;
  final _startCtrl = TextEditingController();
  final _endCtrl   = TextEditingController();

  // Add employee form
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _newRole = 'user';
  String? _addMsg;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final today = await ApiService.getTodayAll();
      final all   = await ApiService.getAllAttendance(start: _startDate, end: _endDate);
      final emps  = await ApiService.getAllEmployees();
      if (!mounted) return;
      setState(() {
        _todayLogs = today;
        _allLogs   = all;
        _employees = emps;
      });
    } catch (e) {
      // Previously swallowed silently, which made a bad date filter look like "no records"
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Could not load data: $e',
            style: const TextStyle(color: Colors.white)),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _exportCSV() async {
    try {
      final path = await ApiService.downloadReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Saved to Downloads:\n$path',
              style: const TextStyle(color: Colors.white, fontSize: 12))),
          ]),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Export failed: $e',
            style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  void _logout() {
    ApiService.clearSession();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LockScreen()), (_) => false,
    );
  }

  String _empName(int id) =>
      _employees.firstWhere((e) => e.id == id,
        orElse: () => Employee(id: 0, name: 'Unknown',
          username: '', role: '', isActive: false)).name;

  String _fmt(DateTime? dt) =>
      dt != null ? DateFormat('hh:mm a').format(dt) : '—';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────
          Container(
            width: 220,
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(right: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const Text('TECHNERDZ',
                  style: TextStyle(fontSize: 11, letterSpacing: 6,
                    color: AppTheme.accentGrey, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('ADMIN PANEL',
                  style: TextStyle(fontSize: 9, letterSpacing: 4,
                    color: AppTheme.accentGrey)),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                ..._pages.asMap().entries.map((e) => _NavItem(
                  label: e.value,
                  index: e.key,
                  selected: _selectedIndex == e.key,
                  icon: [Icons.today, Icons.list_alt, Icons.people][e.key],
                  onTap: () => setState(() => _selectedIndex = e.key),
                )),

                const Spacer(),
                const Divider(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Export CSV',
                      style: TextStyle(fontSize: 12, letterSpacing: 1)),
                    onPressed: _exportCSV,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentGrey,
                      side: const BorderSide(color: AppTheme.border),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('Add Employee',
                      style: TextStyle(fontSize: 12, letterSpacing: 1)),
                    onPressed: () => _showAddEmployee(context),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Sign Out',
                      style: TextStyle(fontSize: 12, letterSpacing: 1)),
                    onPressed: _logout,
                  ),
                ),
              ],
            ),
          ),

          // ── Main Content ─────────────────────────────
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
              : Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_pages[_selectedIndex],
                                style: const TextStyle(fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                              const SizedBox(height: 4),
                              Text(DateFormat('EEEE, MMMM d yyyy').format(DateTime.now()),
                                style: const TextStyle(
                                  color: AppTheme.accentGrey, fontSize: 14)),
                            ],
                          ),
                          Row(children: [
                            const ClockWidget(),
                            const SizedBox(width: 24),
                            IconButton(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh,
                                color: AppTheme.accentGrey),
                              tooltip: 'Refresh',
                            ),
                          ]),
                        ],
                      ),

                      const SizedBox(height: 32),

                      if (_selectedIndex == 0) ...[
                        _StatsRow(
                          total:   _employees.length,
                          present: _todayLogs.length,
                          absent:  _employees.length - _todayLogs.length,
                        ),
                        const SizedBox(height: 32),
                      ],

                      Expanded(child: _buildTable()),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_selectedIndex == 0) {
      return _AttendanceTable(
        logs: _todayLogs, empName: _empName, fmt: _fmt);
    }
    if (_selectedIndex == 1) {
      return Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(children: [
            const Text('FILTER BY DATE',
              style: TextStyle(fontSize: 10, letterSpacing: 2,
                color: AppTheme.accentGrey)),
            const SizedBox(width: 24),
            Expanded(
              child: TextField(
                controller: _startCtrl,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'From (YYYY-MM-DD)', isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                onChanged: (v) => _startDate = v.isEmpty ? null : v,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _endCtrl,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'To (YYYY-MM-DD)', isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                onChanged: (v) => _endDate = v.isEmpty ? null : v,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('FILTER')),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accentGrey,
                side: const BorderSide(color: AppTheme.border)),
              onPressed: () {
                _startCtrl.clear(); _endCtrl.clear();
                _startDate = null; _endDate = null;
                _loadData();
              },
              child: const Text('CLEAR'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _AttendanceTable(
            logs: _allLogs, empName: _empName,
            fmt: _fmt, showDate: true),
        ),
      ]);
    }

    return _EmployeeTableWithSearch(
      employees: _employees,
      onRegisterFace: (emp) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FaceRegisterScreen(
            employeeId: emp.id, employeeName: emp.name),
        )).then((_) => _loadData());
      },
    );
  }

  void _showAddEmployee(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Add Employee',
            style: TextStyle(color: AppTheme.textPrimary)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _nameCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Full Name')),
                const SizedBox(height: 16),
                TextField(controller: _userCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: 16),
                TextField(controller: _passCtrl, obscureText: true,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _newRole,
                  dropdownColor: AppTheme.card,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'user',  child: Text('Employee')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) => setS(() => _newRole = v!),
                ),
                if (_addMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(_addMsg!, style: TextStyle(
                    color: _addMsg!.contains('success')
                      ? AppTheme.success : AppTheme.error,
                    fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                style: TextStyle(color: AppTheme.accentGrey))),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ApiService.registerEmployee(
                    _nameCtrl.text, _userCtrl.text,
                    _passCtrl.text, _newRole,
                  );
                  setS(() => _addMsg = 'Employee added successfully!');
                  _nameCtrl.clear(); _userCtrl.clear(); _passCtrl.clear();
                  await _loadData();
                } on ApiException catch (e) {
                  // e.g. "Username already exists" — used to show "success" anyway
                  setS(() => _addMsg = e.statusCode == 422
                      ? 'Check the fields: username needs 2+ characters, password 6+.'
                      : e.message);
                } catch (_) {
                  setS(() => _addMsg = 'Failed to add employee.');
                }
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Nav Item ──────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final String label; final int index; final bool selected;
  final IconData icon; final VoidCallback onTap;
  const _NavItem({required this.label, required this.index,
    required this.selected, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? AppTheme.card : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppTheme.border : Colors.transparent)),
      child: Row(children: [
        Icon(icon, size: 16,
          color: selected ? AppTheme.textPrimary : AppTheme.accentGrey),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w500,
          color: selected ? AppTheme.textPrimary : AppTheme.accentGrey)),
      ]),
    ),
  );
}

// ── Stats Row ─────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final int total, present, absent;
  const _StatsRow({required this.total, required this.present, required this.absent});

  @override
  Widget build(BuildContext context) => Row(children: [
    _StatCard(label: 'TOTAL EMPLOYEES', value: '$total', color: AppTheme.accentGrey),
    const SizedBox(width: 16),
    _StatCard(label: 'PRESENT TODAY',   value: '$present', color: AppTheme.success),
    const SizedBox(width: 16),
    _StatCard(label: 'ABSENT TODAY',    value: '$absent',  color: AppTheme.error),
  ]);
}

class _StatCard extends StatelessWidget {
  final String label, value; final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10,
          letterSpacing: 2, color: AppTheme.accentGrey)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 32,
          fontWeight: FontWeight.w300, color: color)),
      ]),
    ),
  );
}

// ── Attendance Table ──────────────────────────────────────
class _AttendanceTable extends StatelessWidget {
  final List<AttendanceLog> logs;
  final String Function(int) empName;
  final String Function(DateTime?) fmt;
  final bool showDate;
  const _AttendanceTable({
    required this.logs, required this.empName,
    required this.fmt,  this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
      child: Text('No records found.',
        style: TextStyle(color: AppTheme.accentGrey)));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: SingleChildScrollView(
        child: Table(
          columnWidths: {
            0: const FlexColumnWidth(2),
            if (showDate) 1: const FlexColumnWidth(1.5),
            if (showDate) 2: const FlexColumnWidth(1),
            if (!showDate) 1: const FlexColumnWidth(1),
            if (!showDate) 2: const FlexColumnWidth(1),
            if (!showDate) 3: const FlexColumnWidth(1),
            if (!showDate) 4: const FlexColumnWidth(1),
            if (showDate) 3: const FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border))),
              children: [
                _th('EMPLOYEE'),
                if (showDate) _th('DATE'),
                _th('CHECK IN'),
                _th('CHECK OUT'),
                _th('HOURS'),
                if (!showDate) _th('STATUS'),
              ],
            ),
            ...logs.map((log) => TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.divider))),
              children: [
                _td(empName(log.employeeId)),
                if (showDate) _td(log.date),
                _td(fmt(log.inTime)),
                _td(fmt(log.outTime)),
                _tdHours(log.inTime, log.outTime),
                if (!showDate) _tdStatus(
                  log.outTime != null ? 'COMPLETE'
                    : log.inTime != null ? 'IN' : '—',
                  log.outTime != null ? AppTheme.success
                    : log.inTime != null ? Colors.amber : AppTheme.accentGrey),
              ],
            )),
          ],
        ),
      ),
    );
  }

  Widget _th(String t) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(t, style: const TextStyle(fontSize: 10,
      letterSpacing: 2, color: AppTheme.accentGrey, fontWeight: FontWeight.w600)));

  Widget _td(String t) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(t, style: const TextStyle(
      color: AppTheme.textPrimary, fontSize: 14)));

  Widget _tdStatus(String t, Color c) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(t, style: TextStyle(color: c,
      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)));

  Widget _tdHours(DateTime? inTime, DateTime? outTime) {
    if (inTime == null || outTime == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('--:--', style: TextStyle(
          color: AppTheme.accentGrey, fontSize: 14)));
    }
    final diff = outTime.difference(inTime);
    final h    = diff.inHours.toString().padLeft(2, '0');
    final m    = (diff.inMinutes % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('${h}h ${m}m',
        style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 14)));
  }
}

// ── Employee Table with Search ────────────────────────────
class _EmployeeTableWithSearch extends StatefulWidget {
  final List<Employee> employees;
  final void Function(Employee) onRegisterFace;
  const _EmployeeTableWithSearch(
      {required this.employees, required this.onRegisterFace});

  @override
  State<_EmployeeTableWithSearch> createState() =>
      _EmployeeTableWithSearchState();
}

class _EmployeeTableWithSearchState extends State<_EmployeeTableWithSearch> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.employees.where((e) =>
      e.name.toLowerCase().contains(_query) ||
      e.username.toLowerCase().contains(_query) ||
      e.role.toLowerCase().contains(_query),
    ).toList();

    return Column(
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(children: [
            const Icon(Icons.search, color: AppTheme.accentGrey, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search by name, username or role...',
                  hintStyle: TextStyle(
                    color: AppTheme.accentGrey, fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                child: const Icon(Icons.close,
                  color: AppTheme.accentGrey, size: 16),
              ),
            const SizedBox(width: 8),
            Text('${filtered.length} of ${widget.employees.length}',
              style: const TextStyle(
                color: AppTheme.accentGrey, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _EmployeeTable(
            employees: filtered,
            onRegisterFace: widget.onRegisterFace,
          ),
        ),
      ],
    );
  }
}

// ── Employee Table ────────────────────────────────────────
class _EmployeeTable extends StatefulWidget {
  final List<Employee> employees;
  final void Function(Employee) onRegisterFace;
  const _EmployeeTable({required this.employees, required this.onRegisterFace});

  @override
  State<_EmployeeTable> createState() => _EmployeeTableState();
}

class _EmployeeTableState extends State<_EmployeeTable> {
  final Map<int, int>    _faceCounts   = {};
  final Map<int, double> _attendance   = {};
  final Map<int, String> _attendanceLbl = {};

  @override
  void initState() {
    super.initState();
    _loadFaceCounts();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    try {
      final data = await ApiService.getAttendancePercentage();
      if (mounted) {
        setState(() {
          for (final row in data) {
            final id  = row['employee_id'] as int;
            final pct = (row['percentage'] as num).toDouble();
            final att = row['attended_days'] as int;
            final wor = row['working_days']  as int;
            _attendance[id]    = pct;
            _attendanceLbl[id] = '$att/$wor days';
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFaceCounts() async {
    for (final emp in widget.employees) {
      try {
        final res = await ApiService.getFaceCount(emp.id);
        if (mounted) {
          setState(() => _faceCounts[emp.id] = res['total'] ?? 0);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.employees.isEmpty) {
      return const Center(
      child: Text('No employees found.',
        style: TextStyle(color: AppTheme.accentGrey)));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: SingleChildScrollView(
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1.5),
            5: FlexColumnWidth(2),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border))),
              children: ['NAME', 'USERNAME', 'ROLE', 'STATUS', 'THIS MONTH', 'FACE']
                .map((h) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(h, style: const TextStyle(fontSize: 10,
                    letterSpacing: 2, color: AppTheme.accentGrey,
                    fontWeight: FontWeight.w600)),
                )).toList(),
            ),
            ...widget.employees.map((e) {
              final faceCount    = _faceCounts[e.id];
              final isRegistered = (faceCount ?? 0) > 0;
              final isLoading    = faceCount == null;

              return TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.divider))),
                children: [
                  Padding(padding: const EdgeInsets.all(16),
                    child: Text(e.name, style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14))),
                  Padding(padding: const EdgeInsets.all(16),
                    child: Text(e.username, style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14))),
                  Padding(padding: const EdgeInsets.all(16),
                    child: Text(e.role.toUpperCase(), style: const TextStyle(
                      color: AppTheme.accentGrey, fontSize: 12, letterSpacing: 1))),
                  Padding(padding: const EdgeInsets.all(16),
                    child: Text(e.isActive ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(fontSize: 12, letterSpacing: 1,
                        color: e.isActive ? AppTheme.success : AppTheme.error))),

                  // Attendance % cell
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _attendance[e.id] == null
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accentGrey))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${_attendance[e.id]!.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600,
                                color: _attendance[e.id]! >= 75
                                  ? AppTheme.success
                                  : _attendance[e.id]! >= 50
                                    ? Colors.orange : AppTheme.error,
                              )),
                            const SizedBox(height: 2),
                            Text(_attendanceLbl[e.id] ?? '',
                              style: const TextStyle(
                                fontSize: 10, color: AppTheme.accentGrey)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (_attendance[e.id]! / 100).clamp(0.0, 1.0),
                                backgroundColor: AppTheme.border,
                                valueColor: AlwaysStoppedAnimation(
                                  _attendance[e.id]! >= 75
                                    ? AppTheme.success
                                    : _attendance[e.id]! >= 50
                                      ? Colors.orange : AppTheme.error),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: isLoading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2,
                            color: AppTheme.accentGrey))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Icon(
                                isRegistered
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                                size: 13,
                                color: isRegistered
                                  ? AppTheme.success : AppTheme.accentGrey),
                              const SizedBox(width: 4),
                              Text(
                                isRegistered
                                  ? 'Registered ($faceCount imgs)'
                                  : 'Not registered',
                                style: TextStyle(fontSize: 11,
                                  color: isRegistered
                                    ? AppTheme.success : AppTheme.accentGrey)),
                            ]),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: () => widget.onRegisterFace(e),
                              icon: Icon(
                                isRegistered ? Icons.update : Icons.face,
                                size: 13),
                              label: Text(
                                isRegistered ? 'Update Face' : 'Register Face',
                                style: const TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                foregroundColor: isRegistered
                                  ? AppTheme.accent : AppTheme.accentGrey,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}