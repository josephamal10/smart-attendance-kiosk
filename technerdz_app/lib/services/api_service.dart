import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/employee.dart';

import '../main.dart' show navigatorKey;
import '../screens/lock_screen.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';
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

  // ── Global response handler ───────────────────────────
  // Checks every response for 401 (expired/invalid token)
  static Map<String, dynamic> _handle(http.Response res) {
    if (res.statusCode == 401) {
      // Token expired mid-session
      final wasLoggedIn = _token != null;
      clearSession();
      if (wasLoggedIn) {
        // Show dialog then go to lock screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
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
          }
        });
      }
      return {'detail': 'Session expired. Please login again.'};
    }
    return jsonDecode(res.body);
  }

  // ── Auth ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    // For login, don't use _handle (401 = wrong password, not expiry)
    return jsonDecode(res.body);
  }

  static Future<List<Employee>> getEmployees() async {
    final res = await http.get(
      Uri.parse('$baseUrl/auth/employees'), headers: _headers);
    if (res.statusCode == 401) { _handle(res); return []; }
    final List data = jsonDecode(res.body);
    return data.map((e) => Employee.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> registerEmployee(
      String name, String username, String password, String role) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'name': name, 'username': username,
        'password': password, 'role': role
      }),
    );
    return _handle(res);
  }

  // ── Face ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerFace(
      int employeeId, String direction, File imageFile) async {
    final req = http.MultipartRequest(
      'POST', Uri.parse('$baseUrl/face/register'));
    req.headers['Authorization'] = 'Bearer $_token';
    req.fields['employee_id'] = employeeId.toString();
    req.fields['direction']   = direction;
    req.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final streamed = await req.send();
    final res      = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  static Future<Map<String, dynamic>> getFaceCount(int employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/face/count/$employeeId'), headers: _headers);
    return _handle(res);
  }

  static Future<Map<String, dynamic>> deleteFaceImages(int employeeId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/face/delete/$employeeId'),
      headers: _headers,
    );
    return _handle(res);
  }

  static Future<Map<String, dynamic>> deleteFaceImage(int imageId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/face/image/$imageId'),
      headers: _headers,
    );
    return _handle(res);
  }

  static Future<Map<String, dynamic>> checkBlink(File imageFile) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/face/blink'));
    req.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final streamed = await req.send();
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      return {"success": false, "ear": 0.0, "message": "Server error ${res.statusCode}"};
    }
    return jsonDecode(res.body);
  }

  // ── Attendance ────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyFace(
      File imageFile, {int? employeeId}) async {
    final req = http.MultipartRequest(
      'POST', Uri.parse('$baseUrl/attendance/verify'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    if (employeeId != null) {
      req.fields['employee_id'] = employeeId.toString();
    }
    req.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final streamed = await req.send();
    final res      = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  static Future<AttendanceLog?> getTodayLog(int employeeId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/attendance/today/$employeeId'), headers: _headers);
    if (res.statusCode == 404) return null;
    final data = _handle(res);
    if (data.containsKey('detail')) return null;
    return AttendanceLog.fromJson(data);
  }

  // ── Admin ─────────────────────────────────────────────
  static Future<List<AttendanceLog>> getTodayAll() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/attendance/today'), headers: _headers);
    if (res.statusCode == 401) { _handle(res); return []; }
    final List data = jsonDecode(res.body);
    return data.map((e) => AttendanceLog.fromJson(e)).toList();
  }

  static Future<List<AttendanceLog>> getAllAttendance(
      {String? start, String? end}) async {
    String url = '$baseUrl/admin/attendance/all';
    if (start != null || end != null) {
      url += '?';
      if (start != null) url += 'start=$start&';
      if (end   != null) url += 'end=$end';
    }
    final res = await http.get(Uri.parse(url), headers: _headers);
    if (res.statusCode == 401) { _handle(res); return []; }
    final List data = jsonDecode(res.body);
    return data.map((e) => AttendanceLog.fromJson(e)).toList();
  }

  static Future<String?> downloadReport() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/reports/export'), headers: _headers);
    if (res.statusCode == 401) { _handle(res); return null; }
    // Save to Downloads folder
    final dir      = 'C:\\Users\\${Platform.environment['USERNAME']}\\Downloads';
    final filename = 'attendance_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file     = File('$dir\\$filename');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  static Future<List<dynamic>> getAttendancePercentage({int? month, int? year}) async {
    String url = '$baseUrl/admin/attendance/percentage';
    if (month != null || year != null) {
      url += '?';
      if (month != null) url += 'month=$month&';
      if (year  != null) url += 'year=$year';
    }
    final res = await http.get(Uri.parse(url), headers: _headers);
    if (res.statusCode == 401) { _handle(res); return []; }
    return jsonDecode(res.body);
  }

  static Future<List<Employee>> getAllEmployees() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/employees'), headers: _headers);
    if (res.statusCode == 401) { _handle(res); return []; }
    final List data = jsonDecode(res.body);
    return data.map((e) => Employee.fromJson(e)).toList();
  }
}
