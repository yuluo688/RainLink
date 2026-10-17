#ifndef RUNNER_DESKTOP_INTEGRATION_H_
#define RUNNER_DESKTOP_INTEGRATION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Current-user startup and window-owned tray resources. No core logic lives here.
class DesktopIntegration {
 public:
  DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger);
  ~DesktopIntegration();
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void OnMethod(const flutter::MethodCall<flutter::EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool SetTray(bool enabled);
  bool WriteTray(DWORD operation);
  void ShowWindow();
  void ShowMenu();
  void Emit(const std::string& action);
  bool Notify(const wchar_t* title, const std::wstring& text,
              bool subscription_expiry);

  HWND window_;
  UINT taskbar_created_;
  HICON icon_ = nullptr;
  bool tray_requested_ = false;
  bool tray_visible_ = false;
  bool busy_ = false;
  bool expiry_notification_ = false;
  std::wstring label_ = L"RainLink";
  std::wstring action_label_ = L"\u5f00\u59cb\u8fde\u63a5";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_INTEGRATION_H_
