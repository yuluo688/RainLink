#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>
#include <memory>

#include "flutter_window.h"
#include "utils.h"

namespace {
struct CloseWindowsHandle {
  void operator()(HANDLE handle) const { ::CloseHandle(handle); }
};
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool update_candidate = std::any_of(
      command_line_arguments.begin(), command_line_arguments.end(),
      [](const std::string& argument) {
        return argument.rfind("--rainlink-update-health=", 0) == 0;
      });
  wchar_t executable[32768];
  const DWORD length = ::GetModuleFileNameW(nullptr, executable, 32768);
  if (length == 0 || length >= 32768) return EXIT_FAILURE;
  std::wstring marker(executable, length);
  marker = marker.substr(0, marker.find_last_of(L"\\/")) +
           L"\\.rainlink-updating";
  if (!update_candidate &&
      ::GetFileAttributesW(marker.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return ERROR_BUSY;
  }
  // Only one desktop process per interactive session may use the database.
  // The updater waits for this process to exit before launching its candidate.
  std::unique_ptr<void, CloseWindowsHandle> application_mutex(
      ::CreateMutexW(nullptr, TRUE, L"Local\\RainLink.Desktop"));
  if (!application_mutex) return EXIT_FAILURE;
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    const HWND previous = ::FindWindowW(nullptr, L"RainLink");
    if (previous) {
      ::ShowWindow(previous, SW_RESTORE);
      ::SetForegroundWindow(previous);
    }
    return ERROR_ALREADY_EXISTS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"RainLink", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
