import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/ui.dart';
import 'admin_dashboard.dart';

/// Admin sign-in, reached from the small icon on the kiosk screen.
/// Stays on the stack under the dashboard so that signing out comes back here and
/// then to the kiosk (which waits for this screen to close before reusing the camera).
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final res = await ApiService.login(_userCtrl.text.trim(), _passCtrl.text);
      ApiService.setSession(res['access_token'], res['employee_id'], res['role'], res['name']);
      if (!mounted) return;
      _passCtrl.clear();
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminDashboard()));
      // Dashboard closed (signed out) → back to the kiosk
      ApiService.clearSession();
      if (mounted) Navigator.of(context).pop();
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
          label: const Text('Back to kiosk'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary, padding: EdgeInsets.zero),
        ),
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.admin_panel_settings_outlined, color: AppTheme.primary, size: 26),
        ),
      ),
      const SizedBox(height: 20),
      Text('Admin sign-in', style: AppTheme.h1),
      const SizedBox(height: 6),
      Text('For managing employees, faces and attendance records.', style: AppTheme.muted),
      const SizedBox(height: 32),

      Text('Username', style: AppTheme.label),
      const SizedBox(height: 8),
      TextField(
        controller: _userCtrl,
        autofocus: true,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _passFocus.requestFocus(),
        decoration: const InputDecoration(
          hintText: 'Enter your username',
          prefixIcon: Icon(Icons.person_outline, size: 20),
        ),
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
              : const Text('Sign in'),
        ),
      ),
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
          const BrandMark(onDark: true, subtitle: 'Admin console'),
          const Spacer(),
          const Text('Attendance,\nwithout the queue.',
              style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700,
                  height: 1.15, letterSpacing: -1.2)),
          const SizedBox(height: 16),
          Text('Employees just look at the kiosk and blink. You manage people, faces and records here.',
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
    (Icons.face_outlined, 'Face recognition', 'Each employee is recognised from their registered photos'),
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
