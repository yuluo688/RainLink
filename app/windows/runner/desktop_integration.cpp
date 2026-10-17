#include "desktop_integration.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <vector>
#include <limits>
#include <cstring>

#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 100;
constexpr UINT kTrayId = 1;
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunName[] = L"RainLink";
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

bool IsRecoveryLauncher(const std::wstring& path) {
  const HMODULE module = LoadLibraryExW(path.c_str(), nullptr,
      LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
  if (!module) return false;
  const HRSRC resource = FindResourceW(module, MAKEINTRESOURCEW(301), RT_RCDATA);
  const HGLOBAL loaded = resource ? LoadResource(module, resource) : nullptr;
  const void* bytes = loaded ? LockResource(loaded) : nullptr;
  constexpr char kIdentity[] = "RainLink.Bootstrap.Schema2";
  const bool valid = bytes && SizeofResource(module, resource) == sizeof(kIdentity)
      && std::memcmp(bytes, kIdentity, sizeof(kIdentity)) == 0;
  FreeLibrary(module);
  return valid;
}

std::wstring LaunchCommand() {
  std::vector<wchar_t> buffer(32768);
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                        static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= buffer.size()) return {};
  std::wstring executable(buffer.data(), length);
  const auto launcher = executable.substr(0, executable.find_last_of(L"\\/")) + L"\\rainlink.exe";
  // Old Debug output can leave rainlink.exe beside the renamed UI runner.
  // Only the explicit bootstrap resource qualifies as a startup entry.
  if (IsRecoveryLauncher(launcher)) executable = launcher;
  return L"\"" + executable + L"\" --autostart";
}

LSTATUS ReadLaunch(bool* enabled) {
  const auto expected = LaunchCommand();
  if (expected.empty()) return ERROR_PATH_NOT_FOUND;
  DWORD bytes = 0;
  LSTATUS status = RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunName,
                               RRF_RT_REG_SZ, nullptr, nullptr, &bytes);
  if (status == ERROR_FILE_NOT_FOUND) {
    *enabled = false;
    return ERROR_SUCCESS;
  }
  if (status != ERROR_SUCCESS) return status;
  if (bytes > 65536 || bytes % sizeof(wchar_t) != 0) return ERROR_INVALID_DATA;
  std::vector<wchar_t> value(bytes / sizeof(wchar_t) + 1, 0);
  status = RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunName, RRF_RT_REG_SZ,
                       nullptr, value.data(), &bytes);
  if (status == ERROR_SUCCESS) *enabled = expected == value.data();
  return status;
}

LSTATUS WriteLaunch(bool enabled) {
  const auto command = LaunchCommand();
  if (command.empty()) return ERROR_PATH_NOT_FOUND;
  if (!enabled) {
    // Do not delete another installation's startup entry when this copy is off.
    bool owned = false;
    const LSTATUS read = ReadLaunch(&owned);
    if (read != ERROR_SUCCESS || !owned) return read;
  }
  HKEY key = nullptr;
  LSTATUS status = RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0,
                                 KEY_SET_VALUE, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) return status;
  if (enabled) {
    status = RegSetValueExW(key, kRunName, 0, REG_SZ,
                           reinterpret_cast<const BYTE*>(command.c_str()),
                           static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kRunName);
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  if (status != ERROR_SUCCESS) return status;
  bool observed = false;
  status = ReadLaunch(&observed);
  return status == ERROR_SUCCESS && observed != enabled ? ERROR_WRITE_FAULT : status;
}

const Value* Field(const Map* map, const char* key) {
  if (map == nullptr) return nullptr;
  const auto found = map->find(Value(key));
  return found == map->end() ? nullptr : &found->second;
}

bool ReadCount(const Map* map, const char* key, int32_t* result) {
  const Value* value = Field(map, key);
  if (value == nullptr) return false;
  int64_t count = 0;
  if (const auto* count32 = std::get_if<int32_t>(value)) count = *count32;
  else if (const auto* count64 = std::get_if<int64_t>(value)) count = *count64;
  else return false;
  if (count < 0 || count > (std::numeric_limits<int32_t>::max)()) return false;
  *result = static_cast<int32_t>(count);
  return true;
}

bool ReadBool(const Map* map, const char* key, bool* out) {
  const Value* field = Field(map, key);
  const auto* value = field == nullptr ? nullptr : std::get_if<bool>(field);
  if (value == nullptr) return false;
  *out = *value;
  return true;
}

bool ReadText(const Map* map, const char* key, std::wstring* out, size_t maximum) {
  const Value* field = Field(map, key);
  const auto* value = field == nullptr ? nullptr : std::get_if<std::string>(field);
  if (value == nullptr || value->empty() || value->size() > maximum * 4 ||
      value->find('\0') != std::string::npos) return false;
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value->data(), static_cast<int>(value->size()), nullptr, 0);
  if (length <= 0 || static_cast<size_t>(length) > maximum) return false;
  out->resize(length);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(),
      static_cast<int>(value->size()), out->data(), length) == length;
}
}  // namespace

DesktopIntegration::DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window), taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")) {
  icon_ = static_cast<HICON>(LoadImageW(GetModuleHandleW(nullptr),
      MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
      GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "dev.rainlink/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    OnMethod(call, std::move(result));
  });
}

DesktopIntegration::~DesktopIntegration() {
  channel_->SetMethodCallHandler(nullptr);
  if (tray_visible_) WriteTray(NIM_DELETE);
  if (icon_ != nullptr) DestroyIcon(icon_);
}

bool DesktopIntegration::WriteTray(DWORD operation) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, label_.c_str(), _TRUNCATE);
  if (!Shell_NotifyIconW(operation, &data)) return false;
  if (operation == NIM_ADD) {
    data.uVersion = NOTIFYICON_VERSION_4;
    if (!Shell_NotifyIconW(NIM_SETVERSION, &data)) {
      Shell_NotifyIconW(NIM_DELETE, &data);
      return false;
    }
  }
  return true;
}

bool DesktopIntegration::SetTray(bool enabled) {
  if (enabled && !tray_visible_) {
    if (icon_ == nullptr || !WriteTray(NIM_ADD)) return false;
  } else if (!enabled && tray_visible_) {
    ShowWindow();  // Never leave an invisible application without a restore icon.
    if (!WriteTray(NIM_DELETE)) return false;
  }
  tray_requested_ = enabled;
  tray_visible_ = enabled;
  return true;
}

void DesktopIntegration::ShowWindow() {
  ::ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
}

void DesktopIntegration::Emit(const std::string& action) {
  channel_->InvokeMethod("action", std::make_unique<Value>(action));
}

bool DesktopIntegration::Notify(const wchar_t* title, const std::wstring& text,
                                bool subscription_expiry) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
  wcsncpy_s(data.szInfoTitle, title, _TRUNCATE);
  wcsncpy_s(data.szInfo, text.c_str(), _TRUNCATE);
  const bool accepted = tray_visible_ && Shell_NotifyIconW(NIM_MODIFY, &data);
  if (accepted) expiry_notification_ = subscription_expiry;
  return accepted;
}

void DesktopIntegration::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, 1, L"\u663e\u793a RainLink");
  AppendMenuW(menu, MF_STRING | (busy_ ? MF_GRAYED : 0), 2, action_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 3, L"\u9000\u51fa RainLink");
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(window_);
  const int selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                                      point.x, point.y, 0, window_, nullptr);
  DestroyMenu(menu);
  PostMessageW(window_, WM_NULL, 0, 0);
  if (selected == 1) {
    ShowWindow();
    Emit("show");
  } else if (selected == 2 && !busy_) {
    Emit("toggleConnection");
  } else if (selected == 3) {
    Emit("quit");
  }
}

bool DesktopIntegration::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    tray_visible_ = false;
    if (tray_requested_ && !SetTray(true)) {
      ShowWindow();
      Emit("show");
    }
    return true;
  }
  if (message != kTrayMessage) return false;
  const UINT notification = LOWORD(lparam);
  if (notification == NIN_BALLOONUSERCLICK) {
    ShowWindow();
    Emit(expiry_notification_ ? "showGroups" : "show");
    return true;
  }
  if (notification == WM_CONTEXTMENU) ShowMenu();
  if (notification == NIN_SELECT || notification == NIN_KEYSELECT ||
      notification == WM_LBUTTONDBLCLK) {
    ShowWindow();
    Emit("show");
  }
  return true;
}

void DesktopIntegration::OnMethod(const flutter::MethodCall<Value>& call,
                                 std::unique_ptr<flutter::MethodResult<Value>> result) {
  const Map* args = call.arguments() == nullptr ? nullptr : std::get_if<Map>(call.arguments());
  const auto& method = call.method_name();
  if (method == "inspect") {
    bool launch = false;
    if (ReadLaunch(&launch) != ERROR_SUCCESS) {
      result->Error("startup_read_failed", "Cannot read current-user startup setting");
      return;
    }
    result->Success(Value(Map{{Value("launchAtLogin"), Value(launch)},
                              {Value("trayVisible"), Value(tray_visible_)}}));
    return;
  }
  bool flag = false;
  bool success = false;
  if (method == "setLaunchAtLogin" && ReadBool(args, "enabled", &flag)) {
    success = WriteLaunch(flag) == ERROR_SUCCESS;
  } else if (method == "setTrayVisible" && ReadBool(args, "visible", &flag)) {
    success = SetTray(flag);
  } else if (method == "updateTray") {
    std::wstring label, action;
    if (!ReadText(args, "label", &label, 100) || !ReadText(args, "actionLabel", &action, 32) ||
        !ReadBool(args, "busy", &flag)) {
      result->Error("invalid_arguments", "Invalid tray status");
      return;
    }
    label_ = L"RainLink - " + label;
    action_label_ = action;
    busy_ = flag;
    success = !tray_visible_ || WriteTray(NIM_MODIFY);
  } else if (method == "showWindow") {
    ShowWindow();
    success = IsWindowVisible(window_) != FALSE;
  } else if (method == "hideWindow") {
    // Refresh the icon before hiding; an Explorer restart must not strand UI.
    if (tray_visible_ && WriteTray(NIM_MODIFY)) {
      ::ShowWindow(window_, SW_HIDE);
      success = IsWindowVisible(window_) == FALSE;
    }
  } else if (method == "notifyConnection") {
    std::wstring text;
    if (!ReadText(args, "message", &text, 160)) {
      result->Error("invalid_arguments", "Invalid notification");
      return;
    }
    success = Notify(L"RainLink", text, false);
  } else if (method == "notifySubscriptionExpiry") {
    int32_t soon = 0, expired = 0;
    if (!ReadCount(args, "expiringSoon", &soon) ||
        !ReadCount(args, "expired", &expired) || (soon == 0 && expired == 0)) {
      result->Error("invalid_arguments", "Invalid subscription expiry counts");
      return;
    }
    // Build fixed copy from counts only; subscription names can contain URLs
    // or private account information and must never enter an OS notification.
    std::wstring text;
    if (expired > 0) text = std::to_wstring(expired) + L" \u4e2a\u8ba2\u9605\u5df2\u5230\u671f";
    if (soon > 0) {
      if (!text.empty()) text += L"\uff1b";
      text += std::to_wstring(soon) + L" \u4e2a\u8ba2\u9605\u5c06\u5728 3 \u5929\u5185\u5230\u671f";
    }
    text += L"\u3002\u8bf7\u5230\u300c\u5206\u7ec4\u300d\u67e5\u770b\u3002";
    success = Notify(L"RainLink \u00b7 \u8ba2\u9605\u5230\u671f\u63d0\u9192", text, true);
  } else {
    result->Error("invalid_arguments", "Unknown desktop operation or invalid arguments");
    return;
  }
  if (success) result->Success();
  else result->Error("desktop_operation_failed", "Windows did not confirm the desktop operation");
}
