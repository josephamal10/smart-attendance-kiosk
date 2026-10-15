import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// An employee's own dashboard, opened from the kiosk by face (the "My dashboard" icon, or
/// "My attendance" after a check-in). No password: the scan gave a short-lived token for
/// this one person. Closes itself after a while without touches so the next person can't see it.
class MyAttendanceScreen extends StatefulWidget {
  final String token;
  final String name;
  final String? category;
  /// Renders this data instead of calling the server (widget tests).
  final Map<String, dynamic>? demoData;
  const MyAttendanceScreen({super.key, required this.token, required this.name, this.category, this.demoData});

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  static const _idleSeconds = 90;
  Map<String, dynamic>? _data;
  String? _error;
  int _secondsLeft = _idleSeconds;
  Timer? _timer;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loadingMonth = false;
  Map<String, dynamic>? _reportLink; // {url, expires_in_minutes} once asked for
  bool _makingLink = false;

  @override
  void initState() {
    super.initState();
    if (widget.demoData != null) {
      _data = widget.demoData;
    } else {
      _load();
    }
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
      final d = await ApiService.mySummary(widget.token, month: _month);
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Can't reach the attendance server.");
    } finally {
      if (mounted) setState(() => _loadingMonth = false);
    }
  }

  void _shiftMonth(int by) {
    final next = DateTime(_month.year, _month.month + by);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() { _month = next; _loadingMonth = true; _reportLink = null; });
    _load();
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
    if (ok == true && mounted) {
      _toast('Thanks. The admin will check and fix your record.');
      _load();
    }
  }

  Future<void> _makeReportLink() async {
    setState(() => _makingLink = true);
    try {
      final link = await ApiService.myReportLink(widget.token, _month);
      if (mounted) setState(() => _reportLink = link);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (_) {
      if (mounted) _toast("Can't reach the attendance server.", error: true);
    } finally {
      if (mounted) setState(() => _makingLink = false);
    }
  }

  // ── Layout ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _touched(),
      onPointerSignal: (_) => _touched(), // mouse-wheel scrolling counts as activity too
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

  Widget _header() {
    final streak = (_data?['streak']?['current'] as int?) ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        InitialsAvatar(widget.name, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MY DASHBOARD', style: AppTheme.overline),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(child: Text(widget.name, style: AppTheme.h2, overflow: TextOverflow.ellipsis)),
              if (widget.category != null) ...[
                const SizedBox(width: 10),
                StatusBadge(widget.category!, tone: Tone.neutral, dot: false),
              ],
              if (streak > 0) ...[
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Working days in a row arriving on time. Leave and holidays don\'t break it.',
                  child: StatusBadge('$streak-day on-time streak', tone: Tone.warning, dot: false),
                ),
              ],
            ]),
          ]),
        ),
        Text('Closes in $_secondsLeft s', style: AppTheme.muted.copyWith(fontFeatures: AppTheme.tabular)),
        const SizedBox(width: 16),
        ElevatedButton.icon(onPressed: _close, icon: const Icon(Icons.check, size: 18), label: const Text('Done')),
      ]),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final m = Map<String, dynamic>.from(d['month']);
    final avg = m['avg_hours'];
    final ot = (m['overtime_hours'] as num?) ?? 0;
    const gap = SizedBox(width: AppTheme.gap);
    const vgap = SizedBox(height: AppTheme.gap);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: StatCard(label: 'Days present', value: '${m['present']}',
              icon: Icons.how_to_reg_outlined, tone: Tone.success,
              caption: 'of ${m['working_days']} working days so far')),
          gap,
          Expanded(child: StatCard(label: 'Late', value: '${m['late']}',
              icon: Icons.schedule_outlined, tone: m['late'] > 0 ? Tone.warning : Tone.neutral,
              caption: m['late'] == 0 ? 'Always on time' : 'this month')),
          gap,
          Expanded(child: StatCard(label: 'On leave', value: '${m['leave']}',
              icon: Icons.beach_access_outlined, tone: Tone.primary,
              caption: m['absent'] > 0 ? '${m['absent']} day(s) absent' : 'No absences')),
          gap,
          Expanded(child: StatCard(label: 'Average day', value: avg == null ? '—' : '${avg}h',
              icon: Icons.timelapse, tone: Tone.neutral, caption: 'Shift ${d['team']?['shift'] ?? ''}')),
          gap,
          Expanded(child: StatCard(label: 'Overtime', value: ot == 0 ? '—' : '${ot}h',
              icon: Icons.bolt_outlined, tone: ot > 0 ? Tone.primary : Tone.neutral,
              caption: 'beyond your shift, this month')),
        ])),
        vgap,
        // Fixed height: the calendar's week rows and the chart both stretch to fill it
        SizedBox(height: 440, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 4, child: _calendarCard(d)),
          gap,
          Expanded(flex: 5, child: _hoursCard((d['weekly_hours'] as List).cast<Map<String, dynamic>>())),
        ])),
        vgap,
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _leaveCard((d['leave_balance'] as List).cast<Map<String, dynamic>>())),
          gap,
          Expanded(child: _badgesCard(Map<String, dynamic>.from(d['streak']),
              (d['badges'] as List).cast<Map<String, dynamic>>())),
          gap,
          Expanded(child: _updatesCard((d['notices'] as List).cast<Map<String, dynamic>>(),
              (d['updates'] as List).cast<Map<String, dynamic>>())),
        ])),
        vgap,
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _teamCard(Map<String, dynamic>.from(d['team']))),
          gap,
          Expanded(child: _reportCard()),
          gap,
          Expanded(child: _actionsCard()),
        ])),
      ]),
    );
  }

  Widget _cardTitle(String title, {String? subtitle, Widget? trailing}) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.h3),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: AppTheme.muted)],
          ]),
        ),
        if (trailing != null) trailing,
      ]);

  // ── Calendar ─────────────────────────────────────────────

  Widget _calendarCard(Map<String, dynamic> d) {
    final cal = Map<String, dynamic>.from(d['calendar']);
    final days = (cal['days'] as List).cast<Map<String, dynamic>>();
    final cells = ((cal['row']?['cells'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final lead = DateTime.parse(days.first['date']).weekday - 1; // Monday-first grid
    final today = DateFormat('yyyy-MM-dd').format(now);

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Calendar', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_loadingMonth)
            const Padding(padding: EdgeInsets.only(right: 8),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(tooltip: 'Previous month', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
          SizedBox(width: 118, child: Text(cal['month_name'], textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Next month', onPressed: isCurrent ? null : () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right)),
        ])),
        const SizedBox(height: 10),
        Row(children: [
          for (final w in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
            Expanded(child: Text(w.toUpperCase(), textAlign: TextAlign.center,
                style: AppTheme.overline.copyWith(fontSize: 10, letterSpacing: 0.4))),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: Column(children: [
            for (var week = 0; week * 7 < lead + days.length; week++)
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(child: () {
                      final i = week * 7 + col - lead;
                      if (i < 0 || i >= days.length) return const SizedBox.shrink();
                      return _dayCell(days[i], i < cells.length ? cells[i] : const {'status': 'future'},
                          isToday: days[i]['date'] == today);
                    }()),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        const DayLegend(),
      ]),
    );
  }

  Widget _dayCell(Map<String, dynamic> day, Map<String, dynamic> cell, {required bool isToday}) {
    final status = cell['status'] as String;
    final (bg, fg, _, label) = DayStatus.of(status);
    final lines = <String>[
      DateFormat('EEEE, d MMMM').format(DateTime.parse(day['date'])),
      if (status == 'holiday') 'Holiday: ${cell['name']}' else if (status != 'future') label,
      if (cell['in'] != null) 'In ${cell['in']}${cell['out'] != null ? ' · Out ${cell['out']}' : ''}',
      if (cell['worked_minutes'] != null) 'Worked ${formatMinutes(cell['worked_minutes'])}',
      if ((cell['overtime_minutes'] ?? 0) > 0) 'Overtime ${formatMinutes(cell['overtime_minutes'])}',
    ];
    return Tooltip(
      message: lines.join('\n'),
      waitDuration: const Duration(milliseconds: 150),
      child: Container(
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: AppTheme.primary, width: 2) : null,
        ),
        child: Text('${day['day']}', style: TextStyle(
            fontSize: 13, fontWeight: status == 'future' || status == 'off' ? FontWeight.w400 : FontWeight.w600,
            color: status == 'future' ? AppTheme.textSecondary : fg, fontFeatures: AppTheme.tabular)),
      ),
    );
  }

  // ── Weekly hours chart ───────────────────────────────────

  Widget _hoursCard(List<Map<String, dynamic>> weeks) {
    final worked = AppTheme.chartOnTime;
    final expected = AppTheme.borderStrong;
    final top = weeks.fold<double>(0, (a, w) => max(a, max((w['hours'] as num).toDouble(), (w['expected'] as num).toDouble())));
    final step = top <= 20 ? 5.0 : 10.0;
    final maxY = max(step, (top / step).ceil() * step);
    final axis = TextStyle(fontSize: 11, color: AppTheme.textMuted);

    Widget key(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.muted),
        ]);

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Hours per week', subtitle: 'Last 8 weeks, against what your shift expects',
            trailing: Wrap(spacing: 14, children: [key(worked, 'Worked'), key(expected, 'Expected')])),
        const SizedBox(height: 18),
        Expanded(
          child: BarChart(BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < weeks.length; i++)
                  BarChartGroupData(x: i, barsSpace: 3, barRods: [
                    BarChartRodData(toY: (weeks[i]['hours'] as num).toDouble(), width: 12, color: worked,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                    BarChartRodData(toY: (weeks[i]['expected'] as num).toDouble(), width: 12, color: expected,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                  ]),
              ],
              gridData: FlGridData(drawVerticalLine: false, horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.chartGrid, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: step,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}h', style: axis))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: 1,
                    getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(v.toInt() < weeks.length ? weeks[v.toInt()]['label'] : '', style: axis)))),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.surface,
                  tooltipBorder: BorderSide(color: AppTheme.border),
                  tooltipBorderRadius: BorderRadius.circular(8),
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final w = weeks[group.x];
                    if (rodIndex != 0) return null; // one tooltip per week
                    return BarTooltipItem('Week of ${w['label']}\n',
                        TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 12),
                        children: [TextSpan(text: 'Worked ${w['hours']}h\nExpected ${w['expected']}h',
                            style: TextStyle(fontWeight: FontWeight.w400, color: AppTheme.textSecondary, fontSize: 12))]);
                  },
                ),
              ),
            )),
        ),
      ]),
    );
  }

  // ── Leave balance ────────────────────────────────────────

  Widget _leaveCard(List<Map<String, dynamic>> balance) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardTitle('Leave balance', subtitle: '${DateTime.now().year}, in working days'),
          const SizedBox(height: 16),
          if (balance.isEmpty) Text('No leave allowance set.', style: AppTheme.muted),
          for (final b in balance) ...[
            Row(children: [
              Expanded(child: Text('${b['label']} leave', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${b['remaining']}', style: AppTheme.h3.copyWith(fontFeatures: AppTheme.tabular)),
                TextSpan(text: ' of ${b['allowance']} left', style: AppTheme.muted),
              ])),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (b['allowance'] as int) == 0 ? 0 : ((b['used'] as int) / (b['allowance'] as int)).clamp(0.0, 1.0),
                minHeight: 8,
                color: (b['remaining'] as int) == 0 ? AppTheme.warning : AppTheme.primary,
                backgroundColor: AppTheme.border,
              ),
            ),
            const SizedBox(height: 4),
            Text('${b['used']} used${(b['pending'] as int) > 0 ? ' · ${b['pending']} waiting for approval' : ''}',
                style: AppTheme.muted.copyWith(fontSize: 12)),
            const SizedBox(height: 14),
          ],
        ]),
      );

  // ── Streak & badges ──────────────────────────────────────

  static const _badgeIcons = {
    'on_a_roll': Icons.local_fire_department_outlined,
    'perfect_week': Icons.verified_outlined,
    'perfect_month': Icons.emoji_events_outlined,
    'early_bird': Icons.wb_twilight_outlined,
    'clean_exits': Icons.logout,
    'extra_mile': Icons.bolt_outlined,
  };

  Widget _badgesCard(Map<String, dynamic> streak, List<Map<String, dynamic>> badges) {
    final earned = badges.where((b) => b['earned'] == true).length;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Streak & badges', subtitle: '$earned of ${badges.length} badges earned'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _streakTile('Current streak', streak['current'] as int, highlight: true)),
          const SizedBox(width: 10),
          Expanded(child: _streakTile('Best this year', streak['best'] as int)),
        ]),
        const SizedBox(height: 14),
        for (var r = 0; r * 3 < badges.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(children: [
            for (var c = 0; c < 3; c++) ...[
              if (c > 0) const SizedBox(width: 8),
              Expanded(child: r * 3 + c < badges.length ? _badge(badges[r * 3 + c]) : const SizedBox.shrink()),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _streakTile(String label, int days, {bool highlight = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: highlight && days > 0 ? AppTheme.warningSoft : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(children: [
          Icon(Icons.local_fire_department, size: 22,
              color: highlight && days > 0 ? AppTheme.warning : AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$days day${days == 1 ? '' : 's'}', style: AppTheme.h3.copyWith(fontFeatures: AppTheme.tabular)),
            Text(label, style: AppTheme.muted.copyWith(fontSize: 12)),
          ])),
        ]),
      );

  Widget _badge(Map<String, dynamic> b) {
    final on = b['earned'] == true;
    return Tooltip(
      message: '${b['description']}${!on && b['progress'] != null ? '\nProgress: ${b['progress']}' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: on ? AppTheme.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: on ? AppTheme.primary.withValues(alpha: 0.35) : AppTheme.border),
        ),
        child: Column(children: [
          Icon(_badgeIcons[b['key']] ?? Icons.star_outline, size: 22,
              color: on ? AppTheme.primary : AppTheme.textMuted),
          const SizedBox(height: 4),
          Text(b['title'], textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: on ? AppTheme.textPrimary : AppTheme.textSecondary)),
          Text(on ? 'Earned' : (b['progress'] ?? 'Not yet'), style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ]),
      ),
    );
  }

  // ── Notices & updates ────────────────────────────────────

  Widget _updatesCard(List<Map<String, dynamic>> notices, List<Map<String, dynamic>> updates) {
    final when = DateFormat('d MMM');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('Notices & updates'),
        const SizedBox(height: 12),
        if (notices.isEmpty && updates.isEmpty)
          Text('Nothing new. Company notices and replies to your requests show up here.', style: AppTheme.muted),
        for (final n in notices.take(3)) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: n['pinned'] == true ? AppTheme.primarySoft : AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(n['pinned'] == true ? Icons.push_pin : Icons.campaign_outlined, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if ((n['body'] as String).isNotEmpty)
                  Text(n['body'], style: AppTheme.muted.copyWith(fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        if (notices.isNotEmpty && updates.isNotEmpty) const SizedBox(height: 4),
        for (final u in updates.take(4))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Icon(u['type'] == 'leave' ? Icons.beach_access_outlined : Icons.build_outlined,
                  size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(when.format(DateTime.parse(u['at'])), style: AppTheme.muted.copyWith(fontSize: 12)),
              ])),
              StatusBadge(_statusText(u['status']), tone: switch (u['status']) {
                'approved' || 'resolved' => Tone.success,
                'rejected' => Tone.danger,
                _ => Tone.warning,
              }),
            ]),
          ),
      ]),
    );
  }

  // ── Team & holidays ──────────────────────────────────────

  Widget _teamCard(Map<String, dynamic> t) {
    final away = (t['on_leave_today'] as List).cast<String>();
    final holidays = (t['upcoming_holidays'] as List).cast<Map<String, dynamic>>();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle(t['name'] == null ? 'My team' : '${t['name']} team',
            subtitle: t['name'] == null ? 'You are not in a team yet' : '${t['members']} people · shift ${t['shift']}'),
        const SizedBox(height: 14),
        Text('ON LEAVE TODAY', style: AppTheme.overline),
        const SizedBox(height: 6),
        if (away.isEmpty) Text('Everyone is in.', style: AppTheme.muted),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in away) StatusBadge(n, tone: Tone.primary, dot: false),
        ]),
        const SizedBox(height: 16),
        Text('UPCOMING HOLIDAYS', style: AppTheme.overline),
        const SizedBox(height: 6),
        if (holidays.isEmpty) Text('None planned yet.', style: AppTheme.muted),
        for (final h in holidays)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.celebration_outlined, size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(h['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Text('${DateFormat('EEE d MMM').format(DateTime.parse(h['date']))} · '
                  '${h['in_days'] == 0 ? 'today' : h['in_days'] == 1 ? 'tomorrow' : 'in ${h['in_days']} days'}',
                  style: AppTheme.muted.copyWith(fontSize: 12)),
            ]),
          ),
      ]),
    );
  }

  // ── Report (QR to download on a phone) ───────────────────

  Widget _reportCard() {
    final month = DateFormat('MMMM y').format(_month);
    final link = _reportLink;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('My report', subtitle: 'A PDF of $month — every day, hours and overtime'),
        const SizedBox(height: 14),
        if (link == null) ...[
          Text('Nothing is saved on this kiosk. Scan a QR code with your phone to download it.',
              style: AppTheme.muted),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _makingLink ? null : _makeReportLink,
            icon: _makingLink
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.qr_code_2, size: 18),
            label: const Text('Show QR code'),
          ),
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(6),
              color: Colors.white, // QR codes need a light background to scan, even in dark mode
              child: QrImageView(data: link['url'], size: 132, padding: EdgeInsets.zero),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Scan with your phone camera', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Your phone must be on the office Wi-Fi. The link works for '
                  '${link['expires_in_minutes']} minutes.', style: AppTheme.muted.copyWith(fontSize: 12)),
              const SizedBox(height: 8),
              TextButton(onPressed: () => setState(() => _reportLink = null), child: const Text('Hide')),
            ])),
          ]),
      ]),
    );
  }

  Widget _actionsCard() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardTitle('Need something?', subtitle: 'Requests go to the admin for approval.'),
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
}

String _statusText(String s) => switch (s) {
      'pending' => 'Waiting',
      'resolved' => 'Fixed',
      _ => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1),
    };

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
