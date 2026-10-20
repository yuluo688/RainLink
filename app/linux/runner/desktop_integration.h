#ifndef RAINLINK_DESKTOP_INTEGRATION_H_
#define RAINLINK_DESKTOP_INTEGRATION_H_

#include <gtk/gtk.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "desktop_autostart.h"

struct LinuxDesktopStatus {
  bool launch_at_login = false;
  bool tray_visible = false;
  bool tray_available = false;
  bool notifications_available = false;
};

// GTK/GIO implementation shared by the runner channel and native QA tests.
// Every bus request is asynchronous, bounded, and cancelled on destruction.
class LinuxDesktopIntegration
    : public std::enable_shared_from_this<LinuxDesktopIntegration> {
public:
  using Reply = std::function<void(const char *error_code)>;
  using StatusReply =
      std::function<void(const LinuxDesktopStatus &, const char *error_code)>;
  using Action = std::function<void(const std::string &)>;

  LinuxDesktopIntegration(GtkWindow *window, std::string config_directory,
                          std::string executable, Action action);
  ~LinuxDesktopIntegration();

  void Inspect(StatusReply reply);
  void SetLaunchAtLogin(bool enabled, Reply reply);
  void SetTrayVisible(bool visible, Reply reply);
  void UpdateTray(std::string label, std::string action_label, bool busy);
  void ShowWindow();
  void HideWindow(Reply reply);
  void NotifyConnection(const std::string &message, Reply reply);
  void NotifySubscriptionExpiry(int32_t soon, int32_t expired, Reply reply);

private:
  using BusReply = std::function<void(GVariant *, const GError *)>;
  void EnsureBus(Reply reply);
  void FinishBus(GDBusConnection *bus, const GError *error);
  void ClearBus();
  void Call(const char *destination, const char *path, const char *interface,
            const char *method, GVariant *parameters,
            const GVariantType *response_type, BusReply reply);
  void ProbeTray(Reply reply);
  void RegisterTray(Reply reply);
  void CompleteRegistration(const char *error_code);
  void RemoveTray();
  void LostTray();
  void Emit(const char *action);
  void MenuAction(int32_t id);
  GVariant *MenuProperties(int32_t id) const;
  GVariant *MenuLayout(int32_t id, int32_t depth) const;
  GVariant *TrayProperty(const char *property) const;
  void TrayMethod(const char *method, GVariant *arguments,
                  GDBusMethodInvocation *invocation);
  void MenuMethod(const char *method, GVariant *arguments,
                  GDBusMethodInvocation *invocation);
  void PopupMenu(int32_t x, int32_t y);
  void Notify(const std::string &title, const std::string &message, bool expiry,
              Reply reply);

  static const GDBusInterfaceVTable kTrayVtable;
  static const GDBusInterfaceVTable kMenuVtable;
  GtkWindow *window_;
  GtkWidget *popup_menu_ = nullptr;
  DesktopAutostart autostart_;
  Action action_;
  GDBusConnection *bus_ = nullptr;
  GCancellable *cancellable_;
  GCancellable *bus_cancellable_ = nullptr;
  GDBusNodeInfo *tray_info_;
  GDBusNodeInfo *menu_info_;
  GVariant *icon_pixmaps_;
  GdkPixbuf *notification_icon_;
  std::vector<Reply> bus_waiters_;
  guint bus_timeout_ = 0;
  guint watcher_watch_ = 0;
  guint notifier_watch_ = 0;
  guint host_subscription_ = 0;
  guint host_event_subscription_ = 0;
  guint notification_subscription_ = 0;
  gulong closed_handler_ = 0;
  guint tray_registration_ = 0;
  guint menu_registration_ = 0;
  guint tray_name_owner_ = 0;
  uint32_t menu_revision_ = 1;
  uint64_t tray_generation_ = 0;
  uint64_t tray_request_generation_ = 0;
  uint32_t connection_notification_ = 0;
  uint32_t expiry_notification_ = 0;
  bool tray_requested_ = false;
  bool tray_visible_ = false;
  bool host_available_ = false;
  bool notifications_available_ = false;
  std::vector<Reply> registration_waiters_;
  bool busy_ = false;
  std::string watcher_owner_;
  std::string label_ = "未连接";
  std::string action_label_ = "开始连接";
};

#endif // RAINLINK_DESKTOP_INTEGRATION_H_
