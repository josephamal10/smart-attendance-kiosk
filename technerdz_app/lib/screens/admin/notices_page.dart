import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Company notices: shown on the kiosk lock screen and in everyone's "My dashboard".
class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key});
  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  List<Map<String, dynamic>> _notices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final n = await ApiService.getNotices();
      if (mounted) setState(() => _notices = n);
    } catch (e) {
      _toast('Could not load notices: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? AppTheme.danger : null));
  }

  Future<void> _edit([Map<String, dynamic>? notice]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _NoticeDialog(notice: notice));
    if (ok == true) {
      _toast(notice == null ? 'Notice posted. It shows on the kiosk now.' : 'Notice updated.');
      _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${n['title']}"?'),
        content: Text('It disappears from the kiosk and from everyone\'s dashboard.', style: AppTheme.muted),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteNotice(n['id']);
      _toast('Notice removed.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  bool _expired(Map<String, dynamic> n) {
    if (n['expires_on'] == null) return false;
    final today = DateTime.now();
    return DateTime.parse(n['expires_on']).isBefore(DateTime(today.year, today.month, today.day));
  }

  @override
  Widget build(BuildContext context) {
    final live = _notices.where((n) => !_expired(n)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Post short announcements — office closures, events, reminders. '
              'They appear on the kiosk screen and in each person\'s dashboard.', style: AppTheme.muted),
        ),
        if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        if (ApiService.canEdit)
          ElevatedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18),
              label: const Text('New notice')),
      ]),
      const SizedBox(height: 16),
      DataCard(
        header: Text('$live showing now', style: AppTheme.h3),
        empty: const EmptyState(icon: Icons.campaign_outlined, title: 'No notices',
            message: 'Use "New notice" to tell everyone something at the kiosk.'),
        columns: const [Col('Notice', flex: 6), Col('Shown until', flex: 2), Col('Posted', flex: 3),
            Col('', flex: 2, alignEnd: true)],
        rows: [
          for (final n in _notices)
            [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (n['pinned'] == true) ...[
                    Icon(Icons.push_pin, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                  ],
                  Flexible(child: Text(n['title'], style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (_expired(n)) ...[
                    const SizedBox(width: 8),
                    const StatusBadge('Expired', tone: Tone.neutral, dot: false),
                  ],
                ]),
                if ((n['body'] as String).isNotEmpty)
                  Text(n['body'], style: AppTheme.muted, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
              Text(n['expires_on'] == null
                  ? 'Until removed'
                  : DateFormat('d MMM y').format(DateTime.parse(n['expires_on'])), style: AppTheme.body),
              Text('${n['created_by']}\n${DateFormat('d MMM, h:mm a').format(DateTime.parse(n['created_at']))}',
                  style: AppTheme.muted),
              !ApiService.canEdit
                  ? const SizedBox.shrink()
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Edit', onPressed: () => _edit(n),
                          icon: const Icon(Icons.edit_outlined, size: 18)),
                      IconButton(tooltip: 'Remove', onPressed: () => _delete(n),
                          icon: Icon(Icons.delete_outline, size: 20, color: AppTheme.danger)),
                    ]),
            ],
        ],
      ),
    ]);
  }
}

class _NoticeDialog extends StatefulWidget {
  final Map<String, dynamic>? notice;
  const _NoticeDialog({this.notice});
  @override
  State<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<_NoticeDialog> {
  late final _title = TextEditingController(text: widget.notice?['title']);
  late final _body = TextEditingController(text: widget.notice?['body']);
  late bool _pinned = widget.notice?['pinned'] == true;
  late DateTime? _until = widget.notice?['expires_on'] == null ? null : DateTime.parse(widget.notice!['expires_on']);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the notice a title.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.saveNotice(id: widget.notice?['id'], title: _title.text.trim(), body: _body.text.trim(),
          pinned: _pinned, expiresOn: _until);
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
        title: Text(widget.notice == null ? 'New notice' : 'Edit notice'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Title', style: AppTheme.label),
            const SizedBox(height: 6),
            TextField(controller: _title, autofocus: true, maxLength: 120,
                decoration: const InputDecoration(hintText: 'e.g. Office closed on Friday')),
            const SizedBox(height: 8),
            Text('Details (optional)', style: AppTheme.label),
            const SizedBox(height: 6),
            TextField(controller: _body, maxLines: 3, maxLength: 2000,
                decoration: const InputDecoration(hintText: 'e.g. For the building\'s power maintenance.')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Show until', style: AppTheme.label)),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: context, initialDate: _until ?? now.add(const Duration(days: 7)),
                      firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
                  if (d != null) setState(() => _until = d);
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_until == null ? 'Until removed' : DateFormat('d MMM y').format(_until!)),
              ),
              if (_until != null)
                IconButton(tooltip: 'No end date', onPressed: () => setState(() => _until = null),
                    icon: const Icon(Icons.close, size: 18)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('Pin to the top', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('Pinned notices are shown first and highlighted.', style: AppTheme.muted),
            ),
            if (_error != null) ...[const SizedBox(height: 8), InfoBanner(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _saving ? null : _save,
              child: Text(widget.notice == null ? 'Post notice' : 'Save')),
        ],
      );
}
