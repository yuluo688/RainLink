#include "desktop_channel.h"

#include <cstring>
#include <limits>
#include <memory>

#include "desktop_integration.h"

namespace {
using Method = std::shared_ptr<FlMethodCall>;

void Respond(const Method &call, FlValue *result, const char *error_code) {
  g_autoptr(FlMethodResponse) response =
      error_code == nullptr
          ? FL_METHOD_RESPONSE(fl_method_success_response_new(result))
          : FL_METHOD_RESPONSE(fl_method_error_response_new(
                error_code, "Linux did not confirm the desktop operation",
                nullptr));
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call.get(), response, &error)) {
    g_warning("Unable to send desktop operation response");
  }
}

bool Boolean(FlValue *map, const char *key, bool *result) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP)
    return false;
  FlValue *value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL)
    return false;
  *result = fl_value_get_bool(value);
  return true;
}

bool Text(FlValue *map, const char *key, size_t maximum, std::string *result) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP)
    return false;
  FlValue *value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING)
    return false;
  const char *text = fl_value_get_string(value);
  if (text == nullptr || text[0] == '\0' || std::strlen(text) > maximum * 4 ||
      !g_utf8_validate(text, -1, nullptr) ||
      static_cast<size_t>(g_utf8_strlen(text, -1)) > maximum)
    return false;
  for (const char *character = text; *character != '\0'; ++character) {
    if (static_cast<unsigned char>(*character) < 0x20)
      return false;
  }
  *result = text;
  return true;
}

bool Count(FlValue *map, const char *key, int32_t *result) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP)
    return false;
  FlValue *value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT)
    return false;
  const int64_t count = fl_value_get_int(value);
  if (count < 0 || count > std::numeric_limits<int32_t>::max())
    return false;
  *result = static_cast<int32_t>(count);
  return true;
}

class DesktopChannel {
public:
  DesktopChannel(GtkWindow *window, FlBinaryMessenger *messenger) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(messenger, "dev.rainlink/desktop",
                                     FL_METHOD_CODEC(codec));
    g_autofree gchar *executable = g_file_read_link("/proc/self/exe", nullptr);
    integration_ = std::make_shared<LinuxDesktopIntegration>(
        window, g_get_user_config_dir(),
        executable != nullptr ? executable : "",
        [this](const std::string &action) {
          g_autoptr(FlValue) argument = fl_value_new_string(action.c_str());
          fl_method_channel_invoke_method(channel_, "action", argument, nullptr,
                                          nullptr, nullptr);
        });
    fl_method_channel_set_method_call_handler(
        channel_,
        [](FlMethodChannel *, FlMethodCall *call, gpointer data) {
          Method owned(FL_METHOD_CALL(g_object_ref(call)), g_object_unref);
          static_cast<DesktopChannel *>(data)->Handle(owned);
        },
        this, nullptr);
  }

  ~DesktopChannel() {
    integration_.reset();
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_clear_object(&channel_);
  }

private:
  void Handle(const Method &call) {
    const char *method = fl_method_call_get_name(call.get());
    FlValue *arguments = fl_method_call_get_args(call.get());
    auto reply = [call](const char *error) { Respond(call, nullptr, error); };
    bool flag = false;
    if (g_str_equal(method, "inspect")) {
      integration_->Inspect(
          [call](const LinuxDesktopStatus &status, const char *error) {
            g_autoptr(FlValue) result = fl_value_new_map();
            fl_value_set_string_take(result, "launchAtLogin",
                                     fl_value_new_bool(status.launch_at_login));
            fl_value_set_string_take(result, "trayVisible",
                                     fl_value_new_bool(status.tray_visible));
            fl_value_set_string_take(result, "trayAvailable",
                                     fl_value_new_bool(status.tray_available));
            fl_value_set_string_take(
                result, "notificationsAvailable",
                fl_value_new_bool(status.notifications_available));
            fl_value_set_string_take(result, "notificationsRequireTray",
                                     fl_value_new_bool(FALSE));
            Respond(call, result, error);
          });
    } else if (g_str_equal(method, "setLaunchAtLogin") &&
               Boolean(arguments, "enabled", &flag)) {
      integration_->SetLaunchAtLogin(flag, reply);
    } else if (g_str_equal(method, "setTrayVisible") &&
               Boolean(arguments, "visible", &flag)) {
      integration_->SetTrayVisible(flag, reply);
    } else if (g_str_equal(method, "showWindow")) {
      integration_->ShowWindow();
      reply(nullptr);
    } else if (g_str_equal(method, "hideWindow")) {
      integration_->HideWindow(reply);
    } else if (g_str_equal(method, "updateTray")) {
      std::string label, action;
      if (!Text(arguments, "label", 100, &label) ||
          !Text(arguments, "actionLabel", 32, &action) ||
          !Boolean(arguments, "busy", &flag)) {
        reply("invalid_arguments");
        return;
      }
      integration_->UpdateTray(label, action, flag);
      reply(nullptr);
    } else if (g_str_equal(method, "notifyConnection")) {
      std::string message;
      if (!Text(arguments, "message", 160, &message)) {
        reply("invalid_arguments");
        return;
      }
      integration_->NotifyConnection(message, reply);
    } else if (g_str_equal(method, "notifySubscriptionExpiry")) {
      int32_t soon = 0, expired = 0;
      if (!Count(arguments, "expiringSoon", &soon) ||
          !Count(arguments, "expired", &expired)) {
        reply("invalid_arguments");
        return;
      }
      integration_->NotifySubscriptionExpiry(soon, expired, reply);
    } else {
      reply("invalid_arguments");
    }
  }

  FlMethodChannel *channel_;
  std::shared_ptr<LinuxDesktopIntegration> integration_;
};
} // namespace

void rainlink_register_desktop_channel(GtkWindow *window,
                                       FlBinaryMessenger *messenger) {
  g_object_set_data_full(
      G_OBJECT(window), "rainlink-desktop-channel",
      new DesktopChannel(window, messenger),
      [](gpointer data) { delete static_cast<DesktopChannel *>(data); });
  g_signal_connect(window, "destroy",
                   G_CALLBACK(+[](GtkWidget *widget, gpointer) {
                     g_object_set_data(G_OBJECT(widget),
                                       "rainlink-desktop-channel", nullptr);
                   }),
                   nullptr);
}
