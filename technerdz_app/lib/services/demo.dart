import 'package:flutter/foundation.dart';

/// Demo mode details from the server (only sent when it runs the demo database): the demo
/// sign-in accounts and employees whose dashboards visitors can open without a face scan.
class Demo {
  static final ValueNotifier<Map<String, dynamic>?> info = ValueNotifier(null);

  static bool get enabled => info.value != null;

  static List<Map<String, dynamic>> get accounts =>
      ((info.value?['accounts'] as List?) ?? const []).cast<Map<String, dynamic>>();

  static List<Map<String, dynamic>> get employees =>
      ((info.value?['employees'] as List?) ?? const []).cast<Map<String, dynamic>>();

  static void update(Map<String, dynamic> kioskInfo) {
    final d = kioskInfo['demo'];
    info.value = d is Map ? Map<String, dynamic>.from(d) : null;
  }
}
