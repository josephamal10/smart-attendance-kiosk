import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Who can sign in to this dashboard. Super admins change things; HR viewers can only look
/// and export. Only super admins see this page.
class AdminsPage extends StatefulWidget {
  const AdminsPage({super.key});
  @override
  State<AdminsPage> createState() => _AdminsPageState();
}

class _AdminsPageState extends State<AdminsPage> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final a = await ApiService.getAdmins();
      if (mounted) setState(() => _admins = a);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? AppTheme.danger : null));
  }

  Future<void> _change(Map<String, dynamic> a, {String? role, bool? isActive}) async {
    try {
      await ApiService.updateAdmin(a['id'], role: role, isActive: isActive);
      _toast('Saved changes for ${a['name']}.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);  // e.g. "There must always be at least one active super admin."
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> a) async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New password for ${a['name']}'),
        content: SizedBox(
          width: 380,
          child: TextField(controller: ctrl, autofocus: true, obscureText: true,
              decoration: const InputDecoration(hintText: 'New password', prefixIcon: Icon(Icons.lock_outline, size: 20))),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Set password')),
        ],
      ),
    );
    ctrl.dispose();
    if (pw == null || pw.isEmpty) return;
    try {
      await ApiService.updateAdmin(a['id'], password: pw);
      _toast('Password changed. Tell ${a['name']} in person, not by chat.');
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _AddAdminDialog());
    if (ok == true) {
      _toast('Account created. They can sign in now.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Super admins can change anything. HR viewers can see every page and export '
              'reports, but can\'t edit, approve or change settings.', style: AppTheme.muted),
        ),
        if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add account')),
      ]),
      const SizedBox(height: 16),
      DataCard(
        header: Text('${_admins.length} account${_admins.length == 1 ? '' : 's'}', style: AppTheme.h3),
        columns: const [Col('Name', flex: 4), Col('Access', flex: 3), Col('Status', flex: 2),
            Col('', flex: 2, alignEnd: true)],
        rows: [
          for (final a in _admins)
            [
              PersonCell(a['name'], secondary: '@${a['username']}${a['id'] == ApiService.employeeId ? ' · you' : ''}'),
              StatusBadge(a['role'] == 'admin' ? 'Super admin' : 'HR viewer',
                  tone: a['role'] == 'admin' ? Tone.primary : Tone.neutral, dot: false),
              StatusBadge(a['is_active'] == true ? 'Active' : 'Disabled',
                  tone: a['is_active'] == true ? Tone.success : Tone.neutral),
              PopupMenuButton<String>(
                tooltip: 'Change',
                icon: Icon(Icons.more_vert, color: AppTheme.textSecondary),
                onSelected: (v) => switch (v) {
                  'super' => _change(a, role: 'admin'),
                  'viewer' => _change(a, role: 'viewer'),
                  'toggle' => _change(a, isActive: a['is_active'] != true),
                  _ => _resetPassword(a),
                },
                itemBuilder: (_) => [
                  if (a['role'] != 'admin') const PopupMenuItem(value: 'super', child: Text('Make super admin')),
                  if (a['role'] == 'admin') const PopupMenuItem(value: 'viewer', child: Text('Make HR viewer (read-only)')),
                  const PopupMenuItem(value: 'password', child: Text('Set a new password')),
                  if (a['id'] != ApiService.employeeId)
                    PopupMenuItem(value: 'toggle', child: Text(a['is_active'] == true ? 'Disable sign-in' : 'Enable sign-in')),
                ],
              ),
            ],
        ],
      ),
    ]);
  }
}

class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog();
  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String _role = 'viewer';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _user.dispose(); _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Fill in the name, username and password.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.addAdmin(_name.text.trim(), _user.text.trim(), _pass.text, _role);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 422
          ? 'Usernames can only use letters, numbers, dots, dashes and underscores.'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false, IconData? icon}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: AppTheme.label),
        const SizedBox(height: 6),
        TextField(controller: c, obscureText: obscure,
            decoration: InputDecoration(prefixIcon: icon == null ? null : Icon(icon, size: 20))),
        const SizedBox(height: 14),
      ]);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add dashboard account'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field('Full name', _name, icon: Icons.badge_outlined),
            _field('Username', _user, icon: Icons.alternate_email),
            _field('Password', _pass, obscure: true, icon: Icons.lock_outline),
            Text('Access', style: AppTheme.label),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'viewer', label: Text('HR viewer (read-only)')),
                ButtonSegment(value: 'admin', label: Text('Super admin')),
              ],
              selected: {_role},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_error != null) ...[const SizedBox(height: 14), InfoBanner(_error!)],
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Create account')),
        ],
      );
}
