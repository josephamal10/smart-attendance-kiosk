import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Company holidays. They don't count as working days, so nobody is "absent" on them.
class HolidaysPage extends StatefulWidget {
  final VoidCallback onChanged;
  const HolidaysPage({super.key, required this.onChanged});
  @override
  State<HolidaysPage> createState() => _HolidaysPageState();
}

class _HolidaysPageState extends State<HolidaysPage> {
  int _year = DateTime.now().year;
  List<Holiday> _holidays = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final h = await ApiService.getHolidays(year: _year);
      if (mounted) setState(() => _holidays = h);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load holidays: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _AddHolidayDialog(year: _year));
    if (ok == true) {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _delete(Holiday h) async {
    try {
      await ApiService.deleteHoliday(h.id);
      widget.onChanged();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final upcoming = _holidays.where((h) => !h.date.isBefore(DateTime(today.year, today.month, today.day))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(onPressed: () { setState(() => _year--); _load(); }, icon: const Icon(Icons.chevron_left)),
        Text('$_year', style: AppTheme.h2.copyWith(fontFeatures: AppTheme.tabular)),
        IconButton(onPressed: () { setState(() => _year++); _load(); }, icon: const Icon(Icons.chevron_right)),
        const SizedBox(width: 12),
        if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const Spacer(),
        if (ApiService.canEdit)
          ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Add holiday')),
      ]),
      const SizedBox(height: 16),
      if (upcoming.isNotEmpty && _year == today.year) ...[
        InfoBanner('Next holiday: ${upcoming.first.name} on ${DateFormat('EEEE, d MMMM').format(upcoming.first.date)}'
            ' (${upcoming.first.date.difference(DateTime(today.year, today.month, today.day)).inDays} days away)',
            tone: Tone.primary),
        const SizedBox(height: 16),
      ],
      DataCard(
        header: Text('${_holidays.length} holiday${_holidays.length == 1 ? '' : 's'} in $_year', style: AppTheme.h3),
        empty: const EmptyState(icon: Icons.celebration_outlined, title: 'No holidays added',
            message: 'Holidays are skipped when counting attendance, so nobody shows as absent.'),
        columns: const [Col('Date', flex: 3), Col('Day', flex: 2), Col('Holiday', flex: 5), Col('', flex: 1, alignEnd: true)],
        rows: [
          for (final h in _holidays)
            [
              Text(DateFormat('d MMMM y').format(h.date), style: AppTheme.body),
              Text(DateFormat('EEEE').format(h.date), style: AppTheme.muted),
              Row(children: [
                Flexible(child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (h.date.isBefore(DateTime(today.year, today.month, today.day))) ...[
                  const SizedBox(width: 8),
                  const StatusBadge('Past', tone: Tone.neutral, dot: false),
                ],
              ]),
              ApiService.canEdit
                  ? IconButton(tooltip: 'Remove', onPressed: () => _delete(h),
                      icon: Icon(Icons.delete_outline, color: AppTheme.danger, size: 20))
                  : const SizedBox.shrink(),
            ],
        ],
      ),
    ]);
  }
}

class _AddHolidayDialog extends StatefulWidget {
  final int year;
  const _AddHolidayDialog({required this.year});
  @override
  State<_AddHolidayDialog> createState() => _AddHolidayDialogState();
}

class _AddHolidayDialogState extends State<_AddHolidayDialog> {
  late DateTime _date = widget.year == DateTime.now().year ? DateTime.now() : DateTime(widget.year, 1, 1);
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the holiday a name.');
    try {
      await ApiService.addHoliday(_date, _name.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add holiday'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Date', style: AppTheme.label),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _date,
                    firstDate: DateTime(widget.year - 1), lastDate: DateTime(widget.year + 1, 12, 31));
                if (d != null) setState(() => _date = d);
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(DateFormat('EEEE, d MMMM y').format(_date)),
            ),
            const SizedBox(height: 16),
            Text('Name', style: AppTheme.label),
            const SizedBox(height: 6),
            TextField(controller: _name, autofocus: true,
                decoration: const InputDecoration(hintText: 'e.g. Diwali'), onSubmitted: (_) => _save()),
            if (_error != null) ...[const SizedBox(height: 14), InfoBanner(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _save, child: const Text('Add holiday')),
        ],
      );
}
