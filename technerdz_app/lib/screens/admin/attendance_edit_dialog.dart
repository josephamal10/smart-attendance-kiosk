import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Fix an existing record's times, or add a day that was never recorded.
/// Either way a reason is required — it goes into the audit log.
class AttendanceEditDialog extends StatefulWidget {
  final AttendanceLog? log;            // null = add a new record
  final List<Employee> employees;
  final int? employeeId;               // preselected person (add mode)
  final DateTime? date;                // preselected day (add mode)
  final String? suggestedReason;
  const AttendanceEditDialog({super.key, this.log, required this.employees,
      this.employeeId, this.date, this.suggestedReason});

  @override
  State<AttendanceEditDialog> createState() => _AttendanceEditDialogState();
}

class _AttendanceEditDialogState extends State<AttendanceEditDialog> {
  late int? _employeeId = widget.log?.employeeId ?? widget.employeeId;
  late DateTime _date = widget.log != null ? DateTime.parse(widget.log!.date) : (widget.date ?? DateTime.now());
  late TimeOfDay? _in = _tod(widget.log?.inTime) ?? const TimeOfDay(hour: 9, minute: 0);
  late TimeOfDay? _out = _tod(widget.log?.outTime);
  late final _reason = TextEditingController(text: widget.suggestedReason);
  bool _saving = false;
  String? _error;

  bool get _editing => widget.log != null;

  static TimeOfDay? _tod(DateTime? d) => d == null ? null : TimeOfDay(hour: d.hour, minute: d.minute);
  static String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employeeId == null) return setState(() => _error = 'Choose the employee.');
    if (_in == null) return setState(() => _error = 'Set the check-in time.');
    if (_reason.text.trim().length < 3) {
      return setState(() => _error = 'Please write a short reason (it is kept in the audit log).');
    }
    setState(() { _saving = true; _error = null; });
    try {
      final saved = _editing
          ? await ApiService.correctAttendance(widget.log!.id,
              inTime: _hhmm(_in!), outTime: _out == null ? '' : _hhmm(_out!), reason: _reason.text.trim())
          : await ApiService.addAttendance(_employeeId!, _date,
              inTime: _hhmm(_in!), outTime: _out == null ? null : _hhmm(_out!), reason: _reason.text.trim());
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeField(String label, TimeOfDay? value, ValueChanged<TimeOfDay?> onChanged, {bool clearable = false}) =>
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTheme.label),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(context: context,
                      initialTime: value ?? const TimeOfDay(hour: 18, minute: 0));
                  if (t != null) onChanged(t);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(value == null ? 'Not set' : value.format(context)),
              ),
            ),
            if (clearable && value != null)
              IconButton(tooltip: 'Clear', onPressed: () => onChanged(null), icon: const Icon(Icons.close, size: 18)),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final emp = widget.employees.where((e) => e.id == _employeeId).firstOrNull;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_editing ? 'Correct attendance' : 'Add attendance'),
        const SizedBox(height: 4),
        Text(_editing
            ? '${emp?.name ?? 'Employee'} · ${DateFormat('EEEE, d MMM y').format(_date)}'
            : 'For a day the kiosk missed, e.g. while it was offline.',
            style: AppTheme.muted),
      ]),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_editing) ...[
            Text('Employee', style: AppTheme.label),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _employeeId,
              isExpanded: true,
              hint: const Text('Choose a person'),
              items: [
                for (final e in widget.employees)
                  DropdownMenuItem(value: e.id, child: Text('${e.name}${e.category == null ? '' : '  ·  ${e.category}'}')),
              ],
              onChanged: (v) => setState(() => _employeeId = v),
            ),
            const SizedBox(height: 16),
            Text('Date', style: AppTheme.label),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(DateFormat('EEEE, d MMM y').format(_date)),
            ),
            const SizedBox(height: 16),
          ],
          Row(children: [
            _timeField('Check in', _in, (t) => setState(() => _in = t)),
            const SizedBox(width: 12),
            _timeField('Check out', _out, (t) => setState(() => _out = t), clearable: true),
          ]),
          if (widget.log?.autoCheckout == true) ...[
            const SizedBox(height: 12),
            const InfoBanner('This check-out was filled in automatically because none was recorded.',
                tone: Tone.warning),
          ],
          const SizedBox(height: 16),
          Text('Reason', style: AppTheme.label),
          const SizedBox(height: 6),
          TextField(controller: _reason, maxLines: 2,
              decoration: const InputDecoration(hintText: 'e.g. Forgot to check out, confirmed by manager')),
          if (_error != null) ...[const SizedBox(height: 14), InfoBanner(_error!)],
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saving ? null : _save, child: Text(_editing ? 'Save correction' : 'Add record')),
      ],
    );
  }
}
