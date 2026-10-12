import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/employee.dart';

import '../main.dart' show navigatorKey;
import '../screens/lock_screen.dart';

/// Thrown for any non-2xx response, carrying the server's `detail` message.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiService {
  // Override at build/run time: flutter run --dart-define=API_URL=http://192.168.1.10:8000
  static const String baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8000');
  static String? _token;
  static int?    _employeeId;
  static String? _role;
  static String? _name;

  static void setSession(String token, int empId, String role, String name) {
    _token      = token;
    _employeeId = empId;
    _role       = role;
    _name       = name;
  }

  static void clearSession() {
    _token = null; _employeeId = null; _role = null; _name = null;
  }

  static String? get role       => _role;
  static int?    get employeeId => _employeeId;
  static String? get name       => _name;
  static bool    get isLoggedIn => _token != null;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Uri _uri(String path, [Map<String, String?>? query]) {
    final q = {
      for (final e in (query ?? {}).entries)
        if (e.value != null) e.key: e.value!,
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  // ── Global response handler ───────────────────────────
  // Decodes JSON on success; on failure throws ApiException with the server's message.
  // A 401 on a logged-in session means the token expired → show dialog, go to lock screen.
  static dynamic _handle(http.Response res) {
    if (res.statusCode == 401 && _token != null) {
      clearSession();
      _showSessionExpired();
      throw ApiException(401, 'Session expired. Please login again.');
    }
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;

    final detail = body is Map ? body['detail'] : null;
    throw ApiException(
      res.statusCode,
      detail is String ? detail : 'Server error (${res.statusCode})',
    );
  }

  static void _showSessionExpired() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Row(children: [
            Icon(Icons.lock_clock, color: Colors.orange, size: 20),
            SizedBox(width: 10),
            Text('Session Expired',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          ]),
          content: const Text(
            'Your session has expired. Please login again.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx, rootNavigator: true).pop();
                navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LockScreen()),
                  (_) => false,
                );
              },
              child: const Text('LOGIN AGAIN'),
            ),
          ],
        ),
      );
    });
  }

  static Future<dynamic> _multipart(
      String path, File file, [Map<String, String> fields = const {}]) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.fields.addAll(fields);
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final res = await http.Response.fromStream(await req.send());
    return _handle(res);
  }

  // ── Auth ─────────────────────────────────────────────
  /// Returns the token payload, or throws ApiException with the reason
  /// (wrong password, attempts left, locked out...).
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return Map<String, dynamic>.from(_handle(res));
  }

  static Future<List<Employee>> getEmployees() async {
    final res = await http.get(_uri('/auth/employees'));
    final List data = _handle(res);
    return data.map((e) => Employee.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> registerEmployee(
      String name, String username, String password, String role) async {
    final res = await http.post(
      _uri('/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'name': name, 'username': username,
        'password': password, 'role': role
      }),
    );
    return Map<String, dynamic>.from(_handle(res));
  }

  // ── Face ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerFace(
      int employeeId, String direction, File imageFile) async {
    return Map<String, dynamic>.from(await _multipart('/face/register', imageFile, {
      'employee_id': employeeId.toString(),
      'direction': direction,
    }));
  }

  static Future<Map<String, dynamic>> getFaceCount(int employeeId) async {
    final res = await http.get(_uri('/face/count/$employeeId'), headers: _headers);
    return Map<String, dynamic>.from(_handle(res));
  }

  static Future<void> deleteFaceImages(int employeeId) async {
    _handle(await http.delete(_uri('/face/delete/$employeeId'), headers: _headers));
  }

  static Future<void> deleteFaceImage(int imageId) async {
    _handle(await http.delete(_uri('/face/image/$imageId'), headers: _headers));
  }

  // ── Attendance ────────────────────────────────────────
  /// Send one camera frame for the server-side blink check.
  /// Response has `live`, `face_found`, `message`, and `liveness_token` once live.
  static Future<Map<String, dynamic>> sendLivenessFrame(File imageFile) async {
    return Map<String, dynamic>.from(await _multipart('/attendance/liveness', imageFile));
  }

  static Future<Map<String, dynamic>> verifyFace(
      File imageFile, String livenessToken) async {
    return Map<String, dynamic>.from(await _multipart(
      '/attendance/verify', imageFile, {'liveness_token': livenessToken}));
  }

  static Future<AttendanceLog?> getTodayLog(int employeeId) async {
    final res = await http.get(_uri('/attendance/today/$employeeId'), headers: _headers);
    if (res.statusCode == 404) return null;
    return AttendanceLog.fromJson(_handle(res));
  }

  // ── Admin ─────────────────────────────────────────────
  static Future<List<AttendanceLog>> getTodayAll() async {
    final List data = _handle(
      await http.get(_uri('/admin/attendance/today'), headers: _headers));
    return data.map((e) => AttendanceLog.fromJson(e)).toList();
  }

  static Future<List<AttendanceLog>> getAllAttendance(
      {String? start, String? end}) async {
    final List data = _handle(await http.get(
      _uri('/admin/attendance/all', {'start': start, 'end': end}),
      headers: _headers));
    return data.map((e) => AttendanceLog.fromJson(e)).toList();
  }

  static Future<String> downloadReport() async {
    final res = await http.get(_uri('/admin/reports/export'), headers: _headers);
    _handle(res);
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    final dir  = Directory('$home${Platform.pathSeparator}Downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}'
        'attendance_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  static Future<List<dynamic>> getAttendancePercentage({int? month, int? year}) async {
    return _handle(await http.get(
      _uri('/admin/attendance/percentage',
          {'month': month?.toString(), 'year': year?.toString()}),
      headers: _headers));
  }

  static Future<List<Employee>> getAllEmployees() async {
    final List data = _handle(
      await http.get(_uri('/admin/employees'), headers: _headers));
    return data.map((e) => Employee.fromJson(e)).toList();
  }
}
