class Employee {
  final int id;
  final String name;
  final String username;
  final String role;
  final bool isActive;

  Employee({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.isActive,
  });

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id:       j['id'],
    name:     j['name'],
    username: j['username'],
    // The public login list only sends id/name/username
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

  AttendanceLog({
    required this.id,
    required this.employeeId,
    required this.date,
    this.inTime,
    this.outTime,
    required this.status,
  });

  factory AttendanceLog.fromJson(Map<String, dynamic> j) => AttendanceLog(
    id:         j['id'],
    employeeId: j['employee_id'],
    date:       j['date'],
    inTime:     j['in_time']  != null ? DateTime.parse(j['in_time'])  : null,
    outTime:    j['out_time'] != null ? DateTime.parse(j['out_time']) : null,
    status:     j['status'],
  );
}