#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // --kiosk (used by run.bat): full screen, no title bar or borders
  bool kiosk = false;
  for (const auto& arg : command_line_arguments) {
    if (arg == "--kiosk") kiosk = true;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"NanoNino Attendance", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  if (kiosk) {
    HWND hwnd = window.GetHandle();
    MONITORINFO monitor = {sizeof(monitor)};
    ::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &monitor);
    ::SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP);
    const RECT& r = monitor.rcMonitor;
    ::SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left, r.bottom - r.top,
                   SWP_FRAMECHANGED | SWP_NOACTIVATE);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
