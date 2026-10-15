import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Trends over the last 7 / 30 / 90 days.
///
/// Chart rules followed here: one axis per chart, thin marks (bars ≤ 24px with 4px
/// rounded tops, 2px lines, 8px dots with a surface ring), recessive horizontal-only
/// grid, a legend for the two-series chart, hover tooltips on every chart, and the
/// same colour for "late" everywhere. The two series colours were validated for
/// colour-blind separation on both the light and the dark surface.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  int _days = 30;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await ApiService.getAnalytics(days: _days);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load analytics: $e');
    }
  }

  static String _clock(num minutes) {
    final m = minutes.round();
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
            ButtonSegment(value: 90, label: Text('90 days')),
          ],
          selected: {_days},
          showSelectedIcon: false,
          onSelectionChanged: (s) { setState(() => _days = s.first); _load(); },
        ),
        const Spacer(),
        if (d != null) Text('Office starts at ${_clock(_parseHhmm(d['work_start']))}', style: AppTheme.muted),
      ]),
      const SizedBox(height: 16),
      if (_error != null) InfoBanner(_error!),
      if (d == null && _error == null) const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
      if (d != null) ..._content(d),
    ]);
  }

  static int _parseHhmm(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final s = Map<String, dynamic>.from(d['summary']);
    final daily = (d['daily'] as List).cast<Map<String, dynamic>>();
    final teams = (d['teams'] as List).cast<Map<String, dynamic>>();
    final people = (d['punctuality'] as List).cast<Map<String, dynamic>>();
    return [
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: StatCard(label: 'Attendance rate', value: '${s['presence_rate']}%',
            icon: Icons.how_to_reg_outlined, tone: Tone.success, caption: 'Of expected working days')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'On time', value: '${s['on_time_rate']}%',
            icon: Icons.verified_outlined, tone: Tone.primary, caption: 'Of all check-ins')),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Average arrival', value: s['avg_arrival'] == null ? '—' : _clock(s['avg_arrival']),
            icon: Icons.login_rounded, tone: Tone.neutral)),
        const SizedBox(width: AppTheme.gap),
        Expanded(child: StatCard(label: 'Average day', value: s['avg_worked'] == null ? '—' : formatMinutes(s['avg_worked']),
            icon: Icons.timelapse, tone: Tone.neutral, caption: 'Check-in to check-out')),
      ])),
      const SizedBox(height: AppTheme.gap),
      _chartCard('Daily attendance', 'People who checked in each day, split into on time and late.',
          legend: [('On time', AppTheme.chartOnTime), ('Late', AppTheme.chartLate)],
          child: SizedBox(height: 260, child: _dailyChart(daily))),
      const SizedBox(height: AppTheme.gap),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _chartCard('Average arrival time',
            'Across everyone who checked in that day. Grey line: office start (${_clock(_parseHhmm(d['work_start']))}).',
            child: SizedBox(height: 240, child: _arrivalChart(daily, _parseHhmm(d['work_start']))))),
        const SizedBox(width: AppTheme.gap),
        Expanded(flex: 2, child: _chartCard('Late arrivals by team', 'Total late check-ins in this period.',
            child: _teamBars(teams))),
      ]),
      const SizedBox(height: AppTheme.gap),
      _punctuality(people),
    ];
  }

  Widget _chartCard(String title, String subtitle, {required Widget child, List<(String, Color)>? legend}) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.h3),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTheme.muted),
            ])),
            if (legend != null)
              Wrap(spacing: 16, children: [
                for (final (label, color) in legend)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Text(label, style: AppTheme.muted),
                  ]),
              ]),
          ]),
          const SizedBox(height: 20),
          child,
        ]),
      );

  FlTitlesData _titles({required Widget Function(double) bottom, required Widget Function(double) left,
      double? bottomInterval, double? leftInterval, double leftReserved = 36}) => FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 28, interval: bottomInterval,
            getTitlesWidget: (v, meta) => Padding(padding: const EdgeInsets.only(top: 8), child: bottom(v)))),
        leftTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: leftReserved, interval: leftInterval,
            getTitlesWidget: (v, meta) => left(v))),
      );

  TextStyle get _axis => TextStyle(fontSize: 11, color: AppTheme.textMuted, fontFeatures: AppTheme.tabular);

  Widget _dailyChart(List<Map<String, dynamic>> daily) {
    final maxPresent = daily.fold<int>(0, (m, d) => max(m, d['present'] as int));
    // Round the top of the axis up to a whole step so the last label isn't squeezed in
    final step = max(1, (maxPresent / 4).ceil());
    final top = ((maxPresent + 1) / step).ceil() * step;
    final labelEvery = max(1, (daily.length / 7).ceil());
    final barWidth = min(24.0, max(4.0, 600 / daily.length * 0.6));
    final surface = AppTheme.surface;

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: max(4, top).toDouble(),
      barGroups: [
        for (var i = 0; i < daily.length; i++)
          () {
            final day = daily[i];
            final late = (day['late'] as int).toDouble();
            final total = (day['present'] as int).toDouble();
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: total,
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                color: AppTheme.chartOnTime,
                rodStackItems: total == 0 ? [] : [
                  BarChartRodStackItem(0, total - late, AppTheme.chartOnTime),
                  // The surface-coloured edge acts as the 2px gap between stacked segments
                  BarChartRodStackItem(total - late, total, AppTheme.chartLate,
                      borderSide: BorderSide(color: surface, width: late > 0 && late < total ? 1 : 0)),
                ],
              ),
            ]);
          }(),
      ],
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: step.toDouble(),
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.chartGrid, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: _titles(
        bottomInterval: 1,
        bottom: (v) {
          final i = v.toInt();
          if (i % labelEvery != 0 || i >= daily.length) return const SizedBox.shrink();
          return Text(DateFormat('d MMM').format(DateTime.parse(daily[i]['date'])), style: _axis);
        },
        leftInterval: step.toDouble(),
        left: (v) => Text(v.toInt().toString(), style: _axis),
        leftReserved: 28,
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppTheme.surface,
          tooltipBorder: BorderSide(color: AppTheme.border),
          tooltipBorderRadius: BorderRadius.circular(8),
          getTooltipItem: (group, _, __, ___) {
            final day = daily[group.x];
            final date = DateFormat('EEE, d MMM').format(DateTime.parse(day['date']));
            final present = day['present'] as int, late = day['late'] as int;
            final extra = day['holiday'] != null ? '\nHoliday: ${day['holiday']}'
                : day['working'] == false ? '\nDay off' : '';
            return BarTooltipItem('$date\n', TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 12),
                children: [
                  TextSpan(text: 'On time: ${present - late}\nLate: $late'
                      '${(day['on_leave'] as int) > 0 ? '\nOn leave: ${day['on_leave']}' : ''}$extra',
                      style: TextStyle(fontWeight: FontWeight.w400, color: AppTheme.textSecondary, fontSize: 12)),
                ]);
          },
        ),
      ),
    ));
  }

  Widget _arrivalChart(List<Map<String, dynamic>> daily, int startMinutes) {
    final points = <FlSpot>[
      for (var i = 0; i < daily.length; i++)
        if (daily[i]['avg_arrival'] != null) FlSpot(i.toDouble(), (daily[i]['avg_arrival'] as num).toDouble()),
    ];
    if (points.isEmpty) {
      return const EmptyState(icon: Icons.show_chart, title: 'No check-ins yet', message: 'Arrival times appear here.');
    }
    final ys = [...points.map((p) => p.y), startMinutes.toDouble()];
    final minY = ((ys.reduce(min) - 15) / 15).floor() * 15.0;
    final maxY = ((ys.reduce(max) + 15) / 15).ceil() * 15.0;
    final labelEvery = max(1, (daily.length / 6).ceil());
    final line = AppTheme.chartOnTime;
    final surface = AppTheme.surface;

    return LineChart(LineChartData(
      minX: 0, maxX: (daily.length - 1).toDouble(), minY: minY, maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: points,
          color: line,
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: points.length <= 31,
            getDotPainter: (_, __, ___, ____) =>
                FlDotCirclePainter(radius: 4, color: line, strokeWidth: 2, strokeColor: surface),
          ),
        ),
      ],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: startMinutes.toDouble(), color: AppTheme.textMuted, strokeWidth: 1,
          // Explained in the card subtitle instead of a label that would sit on the data
        ),
      ]),
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: 15,
          getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.chartGrid, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: _titles(
        bottomInterval: 1,
        bottom: (v) {
          final i = v.toInt();
          if (v != i.toDouble() || i % labelEvery != 0 || i >= daily.length) return const SizedBox.shrink();
          return Text(DateFormat('d MMM').format(DateTime.parse(daily[i]['date'])), style: _axis);
        },
        leftInterval: 15,
        left: (v) => (v - minY) % 30 == 0 ? Text(_clock(v), style: _axis) : const SizedBox.shrink(),
        leftReserved: 64,
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppTheme.surface,
          tooltipBorder: BorderSide(color: AppTheme.border),
          tooltipBorderRadius: BorderRadius.circular(8),
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${DateFormat('EEE, d MMM').format(DateTime.parse(daily[s.x.toInt()]['date']))}\n',
                TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 12),
                children: [TextSpan(text: 'Average arrival ${_clock(s.y)}',
                    style: TextStyle(fontWeight: FontWeight.w400, color: AppTheme.textSecondary, fontSize: 12))],
              ),
          ],
        ),
      ),
    ));
  }

  /// Horizontal bars as plain widgets: one measure, so one colour (the same "late" orange).
  Widget _teamBars(List<Map<String, dynamic>> teams) {
    if (teams.isEmpty) {
      return const EmptyState(icon: Icons.groups_outlined, title: 'No teams yet', message: 'Add employees with a team.');
    }
    final sorted = [...teams]..sort((a, b) => (b['late'] as int).compareTo(a['late'] as int));
    final most = max(1, sorted.first['late'] as int);
    return Column(children: [
      for (final t in sorted)
        Tooltip(
          message: '${t['team']}: ${t['late']} late · ${t['presence_pct']}% attendance · '
              '${t['members']} member${t['members'] == 1 ? '' : 's'}'
              '${t['avg_arrival'] == null ? '' : ' · arrives ~${_clock(t['avg_arrival'])}'}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox(width: 120, child: Text(t['team'], style: AppTheme.body, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: LayoutBuilder(builder: (_, c) {
                  final w = c.maxWidth * (t['late'] as int) / most;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: (t['late'] as int) == 0 ? 2 : max(4, w),
                      height: 16,
                      decoration: BoxDecoration(
                        color: (t['late'] as int) == 0 ? AppTheme.border : AppTheme.chartLate,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 28, child: Text('${t['late']}', textAlign: TextAlign.right,
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w600, fontFeatures: AppTheme.tabular))),
            ]),
          ),
        ),
    ]);
  }

  Widget _punctuality(List<Map<String, dynamic>> people) {
    final top = people.take(5).toList();
    final attention = people.reversed.where((p) => (p['late_days'] as int) > 0).take(5).toList();
    Widget table(String title, String subtitle, List<Map<String, dynamic>> rows, IconData icon) => DataCard(
          header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 18, color: AppTheme.textSecondary), const SizedBox(width: 8), Text(title, style: AppTheme.h3)]),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTheme.muted),
          ]),
          empty: const EmptyState(icon: Icons.emoji_events_outlined, title: 'Nothing to show', message: 'Not enough check-ins yet.'),
          columns: const [Col('Employee', flex: 4), Col('On time', flex: 2, alignEnd: true), Col('Late days', flex: 2, alignEnd: true)],
          rows: [
            for (final p in rows)
              [
                PersonCell(p['name'], secondary: p['team']),
                Text('${(p['on_time_pct'] as num).toStringAsFixed(0)}%', style: AppTheme.body.copyWith(fontWeight: FontWeight.w600)),
                Text('${p['late_days']} of ${p['present_days']}', style: AppTheme.muted),
              ],
          ],
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: table('Most punctual', 'Highest share of on-time check-ins.', top, Icons.emoji_events_outlined)),
      const SizedBox(width: AppTheme.gap),
      Expanded(child: table('Often late', 'Worth a friendly word.', attention, Icons.flag_outlined)),
    ]);
  }
}
