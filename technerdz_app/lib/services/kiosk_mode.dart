/// Set when the app was started with --kiosk (run.bat does): full screen, no title bar.
/// The only way out is then "Close the kiosk app" in a super admin's account menu.
class KioskMode {
  static bool enabled = false;
}
