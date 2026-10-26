import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Languages for the screens everyone sees at the kiosk (lock screen, camera, check-in result).
/// The admin console stays in English. Chosen on the lock screen and remembered on this PC.
enum KioskLang {
  en('English', 'en'),
  ta('தமிழ்', 'ta'),
  hi('हिन्दी', 'hi');

  final String label;   // shown in its own language
  final String locale;  // for dates (intl)
  const KioskLang(this.label, this.locale);
}

class KioskText {
  static final ValueNotifier<KioskLang> lang = ValueNotifier(KioskLang.en);
  static const _prefKey = 'kiosk_lang';

  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_prefKey);
      lang.value = KioskLang.values.firstWhere((l) => l.name == saved, orElse: () => KioskLang.en);
    } catch (_) {}
  }

  static Future<void> set(KioskLang l) async {
    lang.value = l;
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, l.name);
    } catch (_) {}
  }

  /// The text for [key] in the current language, with {placeholders} filled in.
  static String t(String key, [Map<String, Object> args = const {}]) {
    var s = _strings[lang.value]![key] ?? _strings[KioskLang.en]![key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// "1 hr 20 mins" · "1 மணி நேரம் 20 நிமிடம்" · "1 घंटा 20 मिनट"
  static String duration(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final (hrs, mins) = switch (lang.value) {
      KioskLang.ta => ('$h மணி நேரம்', '$m நிமிடம்'),
      KioskLang.hi => ('$h ${h == 1 ? 'घंटा' : 'घंटे'}', '$m मिनट'),
      KioskLang.en => ('$h hr${h == 1 ? '' : 's'}', '$m min${m == 1 ? '' : 's'}'),
    };
    if (h == 0) return mins;
    return m == 0 ? hrs : '$hrs $mins';
  }

  static String greeting(DateTime now) =>
      t(now.hour < 12 ? 'morning' : now.hour < 17 ? 'afternoon' : 'evening');

  static const Map<KioskLang, Map<String, String>> _strings = {
    KioskLang.en: {
      'morning': 'Good morning',
      'afternoon': 'Good afternoon',
      'evening': 'Good evening',
      'tap_hint': 'Tap anywhere to check in or out',
      'my_dashboard': 'My dashboard',
      'admin': 'Admin',
      'offline': 'Offline — check-in is unavailable right now',
      'privacy': 'Face check-in · your photo is only used to recognise you and is never stored',
      'birthday': 'Happy birthday, {name}!',
      'anniversary': '{name} — {years} years with us today!',
      'anniversary_one': '{name} — 1 year with us today!',
      'how_check_in': 'HOW TO CHECK IN',
      'how_dashboard': 'HOW TO OPEN YOUR DASHBOARD',
      'step1': 'Look at the camera',
      'step1_sub': 'Stand so your face fits the oval',
      'step2': 'Blink once',
      'step2_sub': 'Shows a real person is there',
      'step3': "That's it",
      'step3_sub': 'You are recognised and checked in or out',
      'step3_sub_dash': 'Your dashboard opens',
      'back': 'Back',
      'pill_check_in': 'Look at the camera to check in or out',
      'pill_dashboard': 'Look at the camera to open your dashboard',
      'pill_blink': 'Now blink once',
      'pill_identifying': 'Recognising you...',
      'dash_banner': 'Opening your dashboard — this scan will not check you in or out.',
      'privacy_short': 'Your photo is only used to recognise you and is not stored.',
      'checked_in': 'Checked in',
      'checked_out': 'Checked out',
      'already_in': 'Already checked in',
      'all_done': 'All done for today',
      'on_time': 'On time',
      'late_by': 'Late by {d}',
      'worked': 'Worked {x} today',
      'day_complete': 'Day complete',
      'left_early': 'left {d} early',
      'earlier': 'Checked in earlier today',
      'msg_in': 'Have a great day!',
      'msg_out': 'See you tomorrow!',
      'msg_done': "You've already checked in and out today.",
      'msg_too_soon': 'You just checked in. Scan again later to check out.',
      'back_in': 'Back to the home screen in {n} s',
      'no_camera': 'Camera not available',
      'try_again': 'Try again',
    },
    KioskLang.ta: {
      'morning': 'காலை வணக்கம்',
      'afternoon': 'மதிய வணக்கம்',
      'evening': 'மாலை வணக்கம்',
      'tap_hint': 'வருகையைப் பதிவு செய்ய திரையில் எங்கும் தொடவும்',
      'my_dashboard': 'என் டாஷ்போர்டு',
      'admin': 'நிர்வாகி',
      'offline': 'இணைப்பு இல்லை — இப்போது வருகையைப் பதிவு செய்ய முடியாது',
      'privacy': 'முக அடையாள வருகை · உங்கள் புகைப்படம் அடையாளம் காண மட்டுமே பயன்படும், சேமிக்கப்படாது',
      'birthday': 'இனிய பிறந்தநாள் வாழ்த்துகள், {name}!',
      'anniversary': '{name} — இன்று நம்முடன் {years} ஆண்டுகள்!',
      'anniversary_one': '{name} — இன்று நம்முடன் 1 ஆண்டு!',
      'how_check_in': 'வருகையைப் பதிவு செய்வது எப்படி',
      'how_dashboard': 'உங்கள் டாஷ்போர்டைத் திறப்பது எப்படி',
      'step1': 'கேமராவைப் பாருங்கள்',
      'step1_sub': 'உங்கள் முகம் வட்டத்துக்குள் இருக்கும்படி நில்லுங்கள்',
      'step2': 'ஒருமுறை கண் சிமிட்டுங்கள்',
      'step2_sub': 'நீங்கள் உண்மையான நபர் என்பதைக் காட்டுகிறது',
      'step3': 'அவ்வளவுதான்',
      'step3_sub': 'நீங்கள் அடையாளம் காணப்பட்டு வருகை பதிவாகும்',
      'step3_sub_dash': 'உங்கள் டாஷ்போர்டு திறக்கும்',
      'back': 'பின்செல்',
      'pill_check_in': 'வருகையைப் பதிவு செய்ய கேமராவைப் பாருங்கள்',
      'pill_dashboard': 'டாஷ்போர்டைத் திறக்க கேமராவைப் பாருங்கள்',
      'pill_blink': 'இப்போது ஒருமுறை கண் சிமிட்டுங்கள்',
      'pill_identifying': 'உங்களை அடையாளம் காண்கிறது...',
      'dash_banner': 'உங்கள் டாஷ்போர்டு திறக்கும் — இந்த ஸ்கேன் வருகையைப் பதிவு செய்யாது.',
      'privacy_short': 'உங்கள் புகைப்படம் அடையாளம் காண மட்டுமே பயன்படும், சேமிக்கப்படாது.',
      'checked_in': 'வருகை பதிவானது',
      'checked_out': 'வெளியேற்றம் பதிவானது',
      'already_in': 'ஏற்கனவே வருகை பதிவாகியுள்ளது',
      'all_done': 'இன்றைக்கு எல்லாம் முடிந்தது',
      'on_time': 'சரியான நேரம்',
      'late_by': '{d} தாமதம்',
      'worked': 'இன்று {x} வேலை செய்தீர்கள்',
      'day_complete': 'நாள் முடிந்தது',
      'left_early': '{d} முன்னதாகச் சென்றீர்கள்',
      'earlier': 'இன்று ஏற்கனவே வருகை பதிவானது',
      'msg_in': 'இனிய நாளாக அமையட்டும்!',
      'msg_out': 'நாளை சந்திப்போம்!',
      'msg_done': 'இன்று வருகையும் வெளியேற்றமும் ஏற்கனவே பதிவாகிவிட்டன.',
      'msg_too_soon': 'இப்போதுதான் வருகை பதிவானது. வெளியேற பின்னர் மீண்டும் ஸ்கேன் செய்யுங்கள்.',
      'back_in': '{n} வினாடிகளில் முகப்புத் திரைக்குத் திரும்பும்',
      'no_camera': 'கேமரா கிடைக்கவில்லை',
      'try_again': 'மீண்டும் முயற்சிக்கவும்',
    },
    KioskLang.hi: {
      'morning': 'सुप्रभात',
      'afternoon': 'नमस्कार',
      'evening': 'शुभ संध्या',
      'tap_hint': 'हाज़िरी लगाने के लिए स्क्रीन पर कहीं भी छुएँ',
      'my_dashboard': 'मेरा डैशबोर्ड',
      'admin': 'एडमिन',
      'offline': 'ऑफ़लाइन — अभी हाज़िरी नहीं लग सकती',
      'privacy': 'चेहरे से हाज़िरी · आपकी फ़ोटो सिर्फ़ पहचान के लिए इस्तेमाल होती है, सेव नहीं होती',
      'birthday': 'जन्मदिन की शुभकामनाएँ, {name}!',
      'anniversary': '{name} — आज हमारे साथ {years} साल!',
      'anniversary_one': '{name} — आज हमारे साथ 1 साल!',
      'how_check_in': 'हाज़िरी कैसे लगाएँ',
      'how_dashboard': 'अपना डैशबोर्ड कैसे खोलें',
      'step1': 'कैमरे की ओर देखें',
      'step1_sub': 'चेहरा अंडाकार घेरे के अंदर रखें',
      'step2': 'एक बार पलक झपकाएँ',
      'step2_sub': 'इससे पता चलता है कि सामने असली व्यक्ति है',
      'step3': 'बस हो गया',
      'step3_sub': 'आपकी पहचान होगी और हाज़िरी दर्ज हो जाएगी',
      'step3_sub_dash': 'आपका डैशबोर्ड खुल जाएगा',
      'back': 'वापस',
      'pill_check_in': 'हाज़िरी के लिए कैमरे की ओर देखें',
      'pill_dashboard': 'डैशबोर्ड खोलने के लिए कैमरे की ओर देखें',
      'pill_blink': 'अब एक बार पलक झपकाएँ',
      'pill_identifying': 'आपको पहचाना जा रहा है...',
      'dash_banner': 'आपका डैशबोर्ड खुलेगा — इस स्कैन से हाज़िरी दर्ज नहीं होगी।',
      'privacy_short': 'आपकी फ़ोटो सिर्फ़ पहचान के लिए इस्तेमाल होती है, सेव नहीं होती।',
      'checked_in': 'आगमन दर्ज',
      'checked_out': 'प्रस्थान दर्ज',
      'already_in': 'आगमन पहले ही दर्ज है',
      'all_done': 'आज का काम पूरा',
      'on_time': 'समय पर',
      'late_by': '{d} देर',
      'worked': 'आज {x} काम किया',
      'day_complete': 'दिन पूरा',
      'left_early': '{d} पहले निकले',
      'earlier': 'आज पहले ही आगमन दर्ज है',
      'msg_in': 'आपका दिन शुभ हो!',
      'msg_out': 'कल मिलते हैं!',
      'msg_done': 'आज का आगमन और प्रस्थान पहले ही दर्ज है।',
      'msg_too_soon': 'अभी-अभी आगमन दर्ज हुआ है। प्रस्थान के लिए बाद में स्कैन करें।',
      'back_in': '{n} सेकंड में होम स्क्रीन पर वापस',
      'no_camera': 'कैमरा उपलब्ध नहीं',
      'try_again': 'फिर से कोशिश करें',
    },
  };
}
