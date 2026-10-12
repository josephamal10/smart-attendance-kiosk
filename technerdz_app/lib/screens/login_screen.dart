import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import 'admin_dashboard.dart';
import 'face_verify_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Employee> _employees = [];
  Employee?      _selected;
  final _passCtrl = TextEditingController();
  bool _loading    = false;
  bool _obscure    = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await ApiService.getEmployees();
      if (mounted) setState(() => _employees = list);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect to server.');
    }
  }

  Future<void> _login() async {
    if (_selected == null) {
      setState(() => _error = 'Please select your name.');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final res = await ApiService.login(_selected!.username, _passCtrl.text);
      ApiService.setSession(
        res['access_token'],
        res['employee_id'],
        res['role'],
        res['name'],
      );
      if (!mounted) return;

      // Admin skips face verify → goes straight to dashboard
      if (res['role'] == 'admin') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        );
      } else {
        // Regular user → must verify face
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FaceVerifyScreen(
              role: res['role'],
              employeeId: res['employee_id'],
            ),
          ),
        );
      }
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
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // Left panel — branding
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppTheme.border)),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('TECHNERDZ',
                    style: TextStyle(
                      fontSize: 13, letterSpacing: 8,
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text('Attendance System',
                    style: TextStyle(
                      fontSize: 13, color: AppTheme.accentGrey, letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 48),
                  Icon(Icons.face_retouching_natural,
                    size: 64, color: AppTheme.accentGrey),
                  SizedBox(height: 16),
                  Text('Face Recognition\nPowered by AI',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.accentGrey, fontSize: 13, height: 1.8),
                  ),
                ],
              ),
            ),
          ),

          // Right panel — login form
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Welcome back',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  const Text('Select your name and enter your password',
                    style: TextStyle(color: AppTheme.accentGrey, fontSize: 14),
                  ),
                  const SizedBox(height: 40),

                  // Name dropdown
                  const Text('NAME', style: TextStyle(fontSize: 11,
                    letterSpacing: 2, color: AppTheme.accentGrey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Employee>(
                    value: _selected,
                    dropdownColor: AppTheme.surface,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    hint: const Text('Select your name',
                      style: TextStyle(color: AppTheme.accentGrey)),
                    decoration: const InputDecoration(),
                    items: _employees.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.name),
                    )).toList(),
                    onChanged: (v) => setState(() { _selected = v; _error = null; }),
                  ),
                  const SizedBox(height: 24),

                  // Password
                  const Text('PASSWORD', style: TextStyle(fontSize: 11,
                    letterSpacing: 2, color: AppTheme.accentGrey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      hintText: 'Enter password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.accentGrey, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                      style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                  ],

                  const SizedBox(height: 32),

                  // Login button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.background),
                            )
                          : const Text('SIGN IN'),
                    ),
                  ),

                  const SizedBox(height: 24),

                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('← Back to lock screen',
                      style: TextStyle(color: AppTheme.accentGrey, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}