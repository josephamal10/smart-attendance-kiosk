import 'dart:io';
import 'package:flutter/foundation.dart';

/// Spoken greetings at the kiosk ("Good morning, Priya. You're checked in."), using the speech
/// engine built into Windows, so no extra software is needed. Switched on/off in Settings.
class Voice {
  static bool enabled = true;

  static const _script = r'Add-Type -AssemblyName System.Speech; '
      r'$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak($env:KIOSK_SAY)';

  static void say(String text) {
    if (!enabled || kIsWeb || !Platform.isWindows || text.trim().isEmpty) return;
    // The text travels in an environment variable, never inside the command, so a name can't
    // break out of it. Detached: the kiosk doesn't wait for the speech to finish.
    Process.start('powershell', ['-NoProfile', '-NonInteractive', '-Command', _script],
            environment: {'KIOSK_SAY': text}, mode: ProcessStartMode.detached)
        .then((_) {}, onError: (_) {});
  }
}
