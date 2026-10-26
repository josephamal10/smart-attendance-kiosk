import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/demo.dart';

/// The company name shown on the lock screen, brand mark and sign-in. It comes from the
/// server's settings (Settings → Company name), so renaming the company needs no rebuild.
class Branding {
  static final ValueNotifier<String> name = ValueNotifier('Smart Attendance Kiosk');

  static Future<void> load() async {
    try {
      final info = await ApiService.kioskInfo();
      final n = (info['company_name'] as String? ?? '').trim();
      if (n.isNotEmpty) name.value = n;
      Demo.update(info);
    } catch (_) {
      // Server not up yet: keep the default; the lock screen asks again later
    }
  }
}
