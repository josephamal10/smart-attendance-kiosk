import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../widgets/ui.dart';
import 'admin_dashboard.dart';
import 'face_verify_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Employee> _employees = [];
  Employee? _selected;
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _loadingList = true;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() { _loadingList = true; _error = null; });
    try {
      final list = await ApiService.getEmployees();
      if (mounted) setState(() => _employees = list);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the attendance server. Check that it is running.');
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _login() async {
    if (_selected == null) {
      setState(() => _error = 'Please choose your name.');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final res = await ApiService.login(_selected!.username, _passCtrl.text);
      ApiService.setSession(res['access_token'], res['employee_id'], res['role'], res['name']);
      if (!mounted) return;

      // Admins go to the console; everyone else must pass the face check
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => res['role'] == 'admin'
            ? const AdminDashboard()
            : FaceVerifyScreen(role: res['role'], employeeId: res['employee_id']),
      ));
    } on ApiException catch (e) {
      // Wrong password / attempts left / locked out — the server explains which
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Connection error. Is the server running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Row(children: [
        const Expanded(flex: 5, child: _BrandPanel()),
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _form(),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _form() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary, padding: EdgeInsets.zero),
        ),
      ),
      const SizedBox(height: 24),
      Text('Sign in', style: AppTheme.h1),
      const SizedBox(height: 6),
      Text('Choose your name and enter your password to continue.', style: AppTheme.muted),
      const SizedBox(height: 32),

      Text('Name', style: AppTheme.label),
      const SizedBox(height: 8),
      DropdownButtonFormField<Employee>(
        initialValue: _selected,
        isExpanded: true,
        icon: _loadingList
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.expand_more),
        hint: Text(_loadingList ? 'Loading people...' : 'Select your name'),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline, size: 20)),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
        dropdownColor: AppTheme.surface,
        menuMaxHeight: 360,
        items: _employees.map((e) => DropdownMenuItem(
          value: e,
          child: Row(children: [
            InitialsAvatar(e.name, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(e.name, overflow: TextOverflow.ellipsis)),
          ]),
        )).toList(),
        selectedItemBuilder: (_) => _employees.map((e) => Text(e.name)).toList(),
        onChanged: (v) {
          setState(() { _selected = v; _error = null; });
          _passFocus.requestFocus();
        },
      ),
      const SizedBox(height: 20),

      Text('Password', style: AppTheme.label),
      const SizedBox(height: 8),
      TextField(
        controller: _passCtrl,
        focusNode: _passFocus,
        obscureText: _obscure,
        onSubmitted: (_) => _login(),
        decoration: InputDecoration(
          hintText: 'Enter your password',
          prefixIcon: const Icon(Icons.lock_outline, size: 20),
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),

      if (_error != null) ...[
        const SizedBox(height: 16),
        InfoBanner(_error!),
      ],
      const SizedBox(height: 28),

      SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Continue'),
        ),
      ),
      if (_error != null && _employees.isEmpty && !_loadingList) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loadEmployees,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Try again'),
        ),
      ],
      const SizedBox(height: 24),
      const Row(children: [
        Icon(Icons.info_outline, size: 16, color: AppTheme.textMuted),
        SizedBox(width: 8),
        Expanded(child: Text(
          'Employees confirm with a quick face scan after signing in.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
      ]),
    ]);
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Stack(children: [
        // Soft decorative rings
        Positioned(right: -220, bottom: -220,
            child: _ring(460, 0.07)),
        Positioned(right: -120, bottom: -120,
            child: _ring(260, 0.09)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BrandMark(onDark: true, subtitle: 'Attendance system'),
          const Spacer(),
          const Text('Attendance,\nwithout the queue.',
              style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700,
                  height: 1.15, letterSpacing: -1.2)),
          const SizedBox(height: 16),
          Text('Sign in, look at the camera, blink. Your check-in is recorded in seconds.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16, height: 1.5)),
          const SizedBox(height: 36),
          ..._features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(f.$1, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.$2, style: const TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(f.$3, style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                    ]),
                  ),
                ]),
              )),
          const Spacer(),
          Text('© TECHNERDZ', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        ]),
      ]),
    );
  }

  static const _features = [
    (Icons.face_outlined, 'Face recognition', 'Matched only against your own registered photos'),
    (Icons.visibility_outlined, 'Liveness check', 'A blink proves a real person is present'),
    (Icons.shield_outlined, 'Anti-spoofing', 'Photos and screens are rejected automatically'),
  ];

  Widget _ring(double size, double alpha) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 40),
        ),
      );
}
