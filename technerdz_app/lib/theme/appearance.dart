import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// Light / dark mode, remembered on this computer.
class Appearance {
  static const _key = 'dark_mode';
  static final ValueNotifier<bool> dark = ValueNotifier(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      AppTheme.isDark = prefs.getBool(_key) ?? false;
    } catch (_) {
      AppTheme.isDark = false; // e.g. storage unavailable: just start in light mode
    }
    dark.value = AppTheme.isDark;
  }

  static Future<void> setDark(bool value) async {
    AppTheme.isDark = value;
    dark.value = value;
    try {
      (await SharedPreferences.getInstance()).setBool(_key, value);
    } catch (_) {}
  }

  /// Screens read colours straight from AppTheme, so after a switch every element
  /// rebuilds once. (Cheaper and simpler than threading a theme through every widget.)
  static void rebuildAll(BuildContext root) {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }
    (root as Element).visitChildren(visit);
  }
}
