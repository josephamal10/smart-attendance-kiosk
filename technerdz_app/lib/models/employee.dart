class Employee {
  final int id;
  final String name;
  final String? category; // HR, Project Manager, Admin, Developer, Tester (null = not set yet)
  final String role;
  final bool isActive;

  Employee({
    required this.id,
    required this.name,
    this.category,
    required this.role,
    required this.isActive,
  });

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id:       j['id'],
    name:     j['name'],
    category: j['category'],
    role:     j['role'] ?? 'user',
    isActive: j['is_active'] ?? true,
  );
}

class AttendanceLog {
  final int id;
  final int employeeId;
  final String date;
  final DateTime? inTime;
  final DateTime? outTime;
  final String status;
  final bool autoCheckout;
  /// late, early_leave, half_day, missed_checkout — worked out by the server's work rules
  final List<String> flags;
  final int lateMinutes;
  final int earlyMinutes;
  final int? workedMinutes;
  final int overtimeMinutes;

  AttendanceLog({
    required this.id,
    required this.employeeId,
    required this.date,
    this.inTime,
    this.outTime,
    required this.status,
    this.autoCheckout = false,
    this.flags = const [],
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.workedMinutes,
    this.overtimeMinutes = 0,
  });

  bool get isLate => flags.contains('late');

  factory AttendanceLog.fromJson(Map<String, dynamic> j) => AttendanceLog(
    id:            j['id'],
    employeeId:    j['employee_id'],
    date:          j['date'],
    inTime:        j['in_time']  != null ? DateTime.parse(j['in_time'])  : null,
    outTime:       j['out_time'] != null ? DateTime.parse(j['out_time']) : null,
    status:        j['status'],
    autoCheckout:  j['auto_checkout'] ?? false,
    flags:         ((j['flags'] as List?) ?? const []).cast<String>(),
    lateMinutes:   j['late_minutes'] ?? 0,
    earlyMinutes:  j['early_minutes'] ?? 0,
    workedMinutes: j['worked_minutes'],
    overtimeMinutes: j['overtime_minutes'] ?? 0,
  );
}

class Holiday {
  final int id;
  final DateTime date;
  final String name;
  Holiday({required this.id, required this.date, required this.name});
  factory Holiday.fromJson(Map<String, dynamic> j) =>
      Holiday(id: j['id'], date: DateTime.parse(j['date']), name: j['name']);
}

class LeaveRequest {
  final int id;
  final int employeeId;
  final DateTime startDate;
  final DateTime endDate;
  final String kind;    // sick / casual / other
  final String reason;
  final String status;  // pending / approved / rejected
  final DateTime createdAt;
  LeaveRequest({required this.id, required this.employeeId, required this.startDate,
      required this.endDate, required this.kind, required this.reason,
      required this.status, required this.createdAt});

  int get days => endDate.difference(startDate).inDays + 1;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: j['id'],
        employeeId: j['employee_id'],
        startDate: DateTime.parse(j['start_date']),
        endDate: DateTime.parse(j['end_date']),
        kind: j['kind'],
        reason: j['reason'] ?? '',
        status: j['status'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

class CorrectionRequest {
  final int id;
  final int employeeId;
  final DateTime date;
  final String kind;    // missed_checkout / wrong_time / other
  final String note;
  final String status;  // pending / resolved / rejected
  final DateTime createdAt;
  CorrectionRequest({required this.id, required this.employeeId, required this.date,
      required this.kind, required this.note, required this.status, required this.createdAt});
  factory CorrectionRequest.fromJson(Map<String, dynamic> j) => CorrectionRequest(
        id: j['id'],
        employeeId: j['employee_id'],
        date: DateTime.parse(j['date']),
        kind: j['kind'],
        note: j['note'] ?? '',
        status: j['status'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

class AuditEntry {
  final int id;
  final DateTime at;
  final String actorName;
  final String action;
  final int? employeeId;
  final String details;
  final String reason;
  AuditEntry({required this.id, required this.at, required this.actorName, required this.action,
      this.employeeId, required this.details, required this.reason});
  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: j['id'],
        at: DateTime.parse(j['at']),
        actorName: j['actor_name'],
        action: j['action'],
        employeeId: j['employee_id'],
        details: j['details'] ?? '',
        reason: j['reason'] ?? '',
      );
}
