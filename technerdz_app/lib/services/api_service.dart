import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/employee.dart';

import '../main.dart' show navigatorKey, homeScreen;
import 'save_file.dart';

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
  // The web dashboard is served by the API server itself, so by default it talks to its own origin.
  static const String _apiUrl = String.fromEnvironment('API_URL');
  static final String baseUrl =
      _apiUrl.isNotEmpty ? _apiUrl : kIsWeb ? Uri.base.origin : 'http://127.0.0.1:8000';
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
  /// Super admins can change things; "viewer" accounts can only look and export.
  static bool    get canEdit    => _role == 'admin';
  /// Face registration needs the kiosk's camera, so it's only offered in the desktop app.
  static bool    get canRegisterFaces => canEdit && !kIsWeb;

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
                  MaterialPageRoute(builder: (_) => homeScreen()),
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

  // ── Auth (admin only) ────────────────────────────────
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

  static Future<void> changePassword(String current, String next) async {
    _handle(await http.post(
      _uri('/auth/change-password'),
      headers: _headers,
      body: jsonEncode({'current_password': current, 'new_password': next}),
    ));
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

  // ── Kiosk (no login: the face is the identity) ────────
  /// One camera frame for the server-side blink check, under a per-scan session id.
  /// Response has `live`, `face_found`, `message`, and `liveness_token` once live.
  static Future<Map<String, dynamic>> kioskLiveness(File frame, String sessionId) async {
    return Map<String, dynamic>.from(
        await _multipart('/kiosk/liveness', frame, {'session_id': sessionId}));
  }

  /// Identify whoever is in [frame] for their own dashboard — no attendance is recorded.
  static Future<Map<String, dynamic>> kioskIdentify(
      File frame, String sessionId, String livenessToken) async {
    return Map<String, dynamic>.from(await _multipart('/kiosk/identify', frame,
        {'session_id': sessionId, 'liveness_token': livenessToken}));
  }

  /// Identify whoever is in [frame] and record their IN / OUT.
  static Future<Map<String, dynamic>> kioskCheckIn(
      File frame, String sessionId, String livenessToken) async {
    return Map<String, dynamic>.from(await _multipart('/kiosk/check-in', frame,
        {'session_id': sessionId, 'liveness_token': livenessToken}));
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
    return saveBytes('attendance_${DateTime.now().millisecondsSinceEpoch}.csv', res.bodyBytes, mime: 'text/csv');
  }

  static Future<List<dynamic>> getAttendancePercentage({int? month, int? year}) async {
    return _handle(await http.get(
      _uri('/admin/attendance/percentage',
          {'month': month?.toString(), 'year': year?.toString()}),
      headers: _headers));
  }

  static Future<List<String>> getCategories() async {
    final List data = _handle(await http.get(_uri('/admin/categories'), headers: _headers));
    return data.cast<String>();
  }

  static Future<Employee> createEmployee(String name, String category,
      {DateTime? birthday, DateTime? joinedOn}) async {
    return Employee.fromJson(_handle(await http.post(
      _uri('/admin/employees'),
      headers: _headers,
      body: jsonEncode({'name': name, 'category': category,
          'birthday': birthday == null ? null : ymd(birthday),
          'joined_on': joinedOn == null ? null : ymd(joinedOn)}),
    )));
  }

  /// Birthday and join date are always sent (null clears them).
  static Future<Employee> updateEmployee(int id,
      {String? name, String? category, bool? isActive, DateTime? birthday, DateTime? joinedOn}) async {
    return Employee.fromJson(_handle(await http.patch(
      _uri('/admin/employees/$id'),
      headers: _headers,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (category != null) 'category': category,
        if (isActive != null) 'is_active': isActive,
        'birthday': birthday == null ? null : ymd(birthday),
        'joined_on': joinedOn == null ? null : ymd(joinedOn),
      }),
    )));
  }

  static Future<List<Employee>> getAllEmployees() async {
    final List data = _handle(
      await http.get(_uri('/admin/employees'), headers: _headers));
    return data.map((e) => Employee.fromJson(e)).toList();
  }

  // ── Attendance corrections ────────────────────────────
  static Future<AttendanceLog> correctAttendance(int logId,
      {String? inTime, String? outTime, required String reason}) async {
    return AttendanceLog.fromJson(_handle(await http.patch(
      _uri('/admin/attendance/$logId'), headers: _headers,
      body: jsonEncode({
        if (inTime != null) 'in_time': inTime,
        if (outTime != null) 'out_time': outTime,
        'reason': reason,
      }),
    )));
  }

  static Future<AttendanceLog> addAttendance(int employeeId, DateTime date,
      {required String inTime, String? outTime, required String reason}) async {
    return AttendanceLog.fromJson(_handle(await http.post(
      _uri('/admin/attendance'), headers: _headers,
      body: jsonEncode({
        'employee_id': employeeId,
        'date': ymd(date),
        'in_time': inTime,
        if (outTime != null && outTime.isNotEmpty) 'out_time': outTime,
        'reason': reason,
      }),
    )));
  }

  static String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Holidays ─────────────────────────────────────────
  static Future<List<Holiday>> getHolidays({int? year}) async {
    final List data = _handle(await http.get(
        _uri('/admin/holidays', {'year': year?.toString()}), headers: _headers));
    return data.map((e) => Holiday.fromJson(e)).toList();
  }

  static Future<void> addHoliday(DateTime date, String name) async {
    _handle(await http.post(_uri('/admin/holidays'), headers: _headers,
        body: jsonEncode({'date': ymd(date), 'name': name})));
  }

  static Future<void> deleteHoliday(int id) async {
    _handle(await http.delete(_uri('/admin/holidays/$id'), headers: _headers));
  }

  // ── Leave & correction requests ──────────────────────
  static Future<List<LeaveRequest>> getLeave({String? status}) async {
    final List data = _handle(await http.get(
        _uri('/admin/leave', {'status': status}), headers: _headers));
    return data.map((e) => LeaveRequest.fromJson(e)).toList();
  }

  static Future<void> addLeave(int employeeId, DateTime start, DateTime end, String kind, String reason) async {
    _handle(await http.post(_uri('/admin/leave'), headers: _headers, body: jsonEncode({
      'employee_id': employeeId, 'start_date': ymd(start), 'end_date': ymd(end),
      'kind': kind, 'reason': reason,
    })));
  }

  static Future<void> decideLeave(int id, bool approve) async {
    _handle(await http.post(_uri('/admin/leave/$id/decision'), headers: _headers,
        body: jsonEncode({'status': approve ? 'approved' : 'rejected'})));
  }

  static Future<List<CorrectionRequest>> getCorrections({String? status}) async {
    final List data = _handle(await http.get(
        _uri('/admin/corrections', {'status': status}), headers: _headers));
    return data.map((e) => CorrectionRequest.fromJson(e)).toList();
  }

  static Future<void> decideCorrection(int id, bool resolved) async {
    _handle(await http.post(_uri('/admin/corrections/$id/decision'), headers: _headers,
        body: jsonEncode({'status': resolved ? 'resolved' : 'rejected'})));
  }

  // ── Insights ─────────────────────────────────────────
  static Future<Map<String, dynamic>> getAnalytics({int days = 30}) async {
    return Map<String, dynamic>.from(_handle(await http.get(
        _uri('/admin/analytics', {'days': '$days'}), headers: _headers)));
  }

  static Future<List<AuditEntry>> getAudit({int limit = 300}) async {
    final List data = _handle(await http.get(
        _uri('/admin/audit', {'limit': '$limit'}), headers: _headers));
    return data.map((e) => AuditEntry.fromJson(e)).toList();
  }

  // ── Settings ─────────────────────────────────────────
  static Future<Map<String, dynamic>> getSettings() async {
    return Map<String, dynamic>.from(_handle(await http.get(_uri('/admin/settings'), headers: _headers)));
  }

  static Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> settings) async {
    final body = Map<String, dynamic>.from(settings)..remove('smtp_configured');
    return Map<String, dynamic>.from(_handle(await http.put(
        _uri('/admin/settings'), headers: _headers, body: jsonEncode(body))));
  }

  static Future<String> sendTestEmail() async {
    final res = _handle(await http.post(_uri('/admin/settings/test-email'), headers: _headers));
    return res['message'] as String;
  }

  // ── Self-service (token from a kiosk check-in, not the admin session) ──
  static Map<String, String> _self(String token) =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};

  /// Self-service calls must not trigger the admin "session expired" dialog,
  /// so they check the status themselves instead of using [_handle].
  static dynamic _handleSelf(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final detail = body is Map ? body['detail'] : null;
    throw ApiException(res.statusCode, detail is String ? detail : 'Please try again.');
  }

  /// Everything on "My dashboard". [month] picks the calendar month (default: this month).
  static Future<Map<String, dynamic>> mySummary(String token, {DateTime? month}) async {
    return Map<String, dynamic>.from(_handleSelf(await http.get(
        _uri('/me', {'year': month?.year.toString(), 'month': month?.month.toString()}),
        headers: _self(token))));
  }

  /// A short-lived link to the same PDF, shown as a QR code for phones.
  static Future<Map<String, dynamic>> myReportLink(String token, DateTime month) async {
    return Map<String, dynamic>.from(_handleSelf(await http.post(
        _uri('/me/report-link', {'year': '${month.year}', 'month': '${month.month}'}), headers: _self(token))));
  }

  /// What the lock screen needs before anyone signs in: company name, today's birthdays and
  /// work anniversaries, and whether to speak greetings.
  static Future<Map<String, dynamic>> kioskInfo() async {
    final res = await http.get(_uri('/kiosk/info')).timeout(const Duration(seconds: 8));
    return Map<String, dynamic>.from(_handleSelf(res));
  }

  static Future<String> companyName() async => (await kioskInfo())['company_name'] as String;

  // ── One-day shift changes (admin) ────────────────────
  static Future<List<Map<String, dynamic>>> getShiftChanges({String? status}) async {
    return (_handle(await http.get(_uri('/admin/shift-changes', {'status': status}), headers: _headers)) as List)
        .cast<Map<String, dynamic>>();
  }

  static Future<void> decideShiftChange(int id, bool approve) async {
    _handle(await http.post(_uri('/admin/shift-changes/$id/decision'), headers: _headers,
        body: jsonEncode({'status': approve ? 'approved' : 'rejected'})));
  }

  // ── Notices ──────────────────────────────────────────
  /// Current notices for the kiosk lock screen (no sign-in needed).
  static Future<List<Map<String, dynamic>>> kioskNotices() async {
    final res = await http.get(_uri('/notices')).timeout(const Duration(seconds: 8));
    return (_handleSelf(res) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getNotices() async {
    return (_handle(await http.get(_uri('/admin/notices'), headers: _headers)) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> saveNotice({int? id, required String title, required String body,
      required bool pinned, DateTime? expiresOn}) async {
    final payload = jsonEncode({'title': title, 'body': body, 'pinned': pinned,
        'expires_on': expiresOn == null ? null : ymd(expiresOn)});
    _handle(id == null
        ? await http.post(_uri('/admin/notices'), headers: _headers, body: payload)
        : await http.put(_uri('/admin/notices/$id'), headers: _headers, body: payload));
  }

  static Future<void> deleteNotice(int id) async {
    _handle(await http.delete(_uri('/admin/notices/$id'), headers: _headers));
  }

  // ── Admin accounts ───────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAdmins() async {
    return (_handle(await http.get(_uri('/admin/admins'), headers: _headers)) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> addAdmin(String name, String username, String password, String role) async {
    _handle(await http.post(_uri('/admin/admins'), headers: _headers, body: jsonEncode(
        {'name': name, 'username': username, 'password': password, 'role': role})));
  }

  static Future<void> updateAdmin(int id, {String? role, bool? isActive, String? password}) async {
    _handle(await http.patch(_uri('/admin/admins/$id'), headers: _headers, body: jsonEncode({
      if (role != null) 'role': role,
      if (isActive != null) 'is_active': isActive,
      if (password != null) 'password': password,
    })));
  }

  static Future<void> requestLeave(String token, DateTime start, DateTime end, String kind, String reason) async {
    _handleSelf(await http.post(_uri('/me/leave'), headers: _self(token), body: jsonEncode({
      'start_date': ymd(start), 'end_date': ymd(end), 'kind': kind, 'reason': reason,
    })));
  }

  static Future<void> requestShiftChange(String token, DateTime date, String start, String end, String reason) async {
    _handleSelf(await http.post(_uri('/me/shift-change'), headers: _self(token), body: jsonEncode({
      'date': ymd(date), 'start': start, 'end': end, 'reason': reason,
    })));
  }

  static Future<void> reportProblem(String token, DateTime date, String kind, String note) async {
    _handleSelf(await http.post(_uri('/me/corrections'), headers: _self(token), body: jsonEncode({
      'date': ymd(date), 'kind': kind, 'note': note,
    })));
  }

  // ── Monthly register & profiles ──────────────────────
  static Future<Map<String, dynamic>> getRegister(int year, int month) async {
    return Map<String, dynamic>.from(_handle(await http.get(
        _uri('/admin/register', {'year': '$year', 'month': '$month'}), headers: _headers)));
  }

  /// Saves the coloured Excel register to the Downloads folder and returns its path.
  static Future<String> downloadRegisterXlsx(int year, int month) async {
    final res = await http.get(
        _uri('/admin/register.xlsx', {'year': '$year', 'month': '$month'}), headers: _headers);
    _handle(res);
    return saveBytes('attendance-$year-${month.toString().padLeft(2, '0')}.xlsx', res.bodyBytes,
        mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  static Future<Map<String, dynamic>> getProfile(int employeeId, int year, int month) async {
    return Map<String, dynamic>.from(_handle(await http.get(
        _uri('/admin/employees/$employeeId/profile', {'year': '$year', 'month': '$month'}), headers: _headers)));
  }

  // ── Backups ──────────────────────────────────────────
  static Future<Map<String, dynamic>> getBackups() async {
    return Map<String, dynamic>.from(_handle(await http.get(_uri('/admin/settings/backups'), headers: _headers)));
  }

  static Future<String> backupNow() async {
    return _handle(await http.post(_uri('/admin/settings/backups'), headers: _headers))['message'] as String;
  }
}
