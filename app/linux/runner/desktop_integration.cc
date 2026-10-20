#include "desktop_integration.h"

#include <limits>
#include <unistd.h>
#include <utility>

namespace {
constexpr int kBusTimeoutMs = 900;
constexpr char kWatcher[] = "org.kde.StatusNotifierWatcher";
constexpr char kWatcherPath[] = "/StatusNotifierWatcher";
constexpr char kTrayInterface[] = "org.kde.StatusNotifierItem";
constexpr char kTrayPath[] = "/StatusNotifierItem";
constexpr char kMenuInterface[] = "com.canonical.dbusmenu";
constexpr char kMenuPath[] = "/StatusNotifierMenu";
constexpr char kNotifications[] = "org.freedesktop.Notifications";
constexpr char kNotificationsPath[] = "/org/freedesktop/Notifications";
constexpr char kProperties[] = "org.freedesktop.DBus.Properties";
constexpr char kTrayXml[] = R"XML(
<node><interface name="org.kde.StatusNotifierItem">
 <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
 <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
 <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
 <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
 <property name="Category" type="s" access="read"/>
 <property name="Id" type="s" access="read"/>
 <property name="Title" type="s" access="read"/>
 <property name="Status" type="s" access="read"/>
 <property name="WindowId" type="u" access="read"/>
 <property name="IconName" type="s" access="read"/>
 <property name="IconPixmap" type="a(iiay)" access="read"/>
 <property name="IconThemePath" type="s" access="read"/>
 <property name="OverlayIconName" type="s" access="read"/>
 <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
 <property name="AttentionIconName" type="s" access="read"/>
 <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
 <property name="AttentionMovieName" type="s" access="read"/>
 <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
 <property name="ItemIsMenu" type="b" access="read"/>
 <property name="Menu" type="o" access="read"/>
 <signal name="NewTitle"/><signal name="NewIcon"/><signal name="NewToolTip"/>
 <signal name="NewStatus"><arg type="s"/></signal>
</interface></node>)XML";
constexpr char kMenuXml[] = R"XML(
<node><interface name="com.canonical.dbusmenu">
 <method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
 <method name="GetGroupProperties"><arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
 <method name="GetProperty"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
 <method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
 <method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
 <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
 <method name="AboutToShowGroup"><arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/></method>
 <property name="Version" type="u" access="read"/>
 <property name="TextDirection" type="s" access="read"/>
 <property name="Status" type="s" access="read"/>
 <property name="IconThemePath" type="as" access="read"/>
 <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
</interface></node>)XML";

GVariant *EmptyPixmaps() {
  return g_variant_new_array(G_VARIANT_TYPE("(iiay)"), nullptr, 0);
}

GVariant *LoadPixmaps() {
  GVariantBuilder result;
  g_variant_builder_init(&result, G_VARIANT_TYPE("a(iiay)"));
  for (int size : {22, 32}) {
    g_autoptr(GdkPixbuf) icon = gdk_pixbuf_new_from_resource_at_scale(
        "/dev/rainlink/rainlink/rainlink.png", size, size, TRUE, nullptr);
    if (icon == nullptr)
      continue;
    const int width = gdk_pixbuf_get_width(icon);
    const int height = gdk_pixbuf_get_height(icon);
    const int stride = gdk_pixbuf_get_rowstride(icon);
    const int channels = gdk_pixbuf_get_n_channels(icon);
    const guchar *pixels = gdk_pixbuf_read_pixels(icon);
    std::vector<guchar> argb(width * height * 4);
    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < width; ++x) {
        const guchar *pixel = pixels + y * stride + x * channels;
        guchar *target = argb.data() + (y * width + x) * 4;
        target[0] = channels == 4 ? pixel[3] : 255;
        target[1] = pixel[0];
        target[2] = pixel[1];
        target[3] = pixel[2];
      }
    }
    g_variant_builder_add(&result, "(ii@ay)", width, height,
                          g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                                    argb.data(), argb.size(),
                                                    1));
  }
  return g_variant_ref_sink(g_variant_builder_end(&result));
}

bool KnownMenuId(int32_t id) { return id >= 0 && id <= 4; }

struct PendingCall {
  std::weak_ptr<LinuxDesktopIntegration> owner;
  std::function<void(GVariant *, const GError *)> reply;
};
} // namespace

const GDBusInterfaceVTable LinuxDesktopIntegration::kTrayVtable = {
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *method, GVariant *arguments,
       GDBusMethodInvocation *invocation, gpointer data) {
      static_cast<LinuxDesktopIntegration *>(data)->TrayMethod(
          method, arguments, invocation);
    },
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *property, GError **, gpointer data) -> GVariant * {
      return static_cast<LinuxDesktopIntegration *>(data)->TrayProperty(
          property);
    },
    nullptr,
    {nullptr}};

const GDBusInterfaceVTable LinuxDesktopIntegration::kMenuVtable = {
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *method, GVariant *arguments,
       GDBusMethodInvocation *invocation, gpointer data) {
      static_cast<LinuxDesktopIntegration *>(data)->MenuMethod(
          method, arguments, invocation);
    },
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *property, GError **, gpointer) -> GVariant * {
      if (g_str_equal(property, "Version"))
        return g_variant_new_uint32(3);
      if (g_str_equal(property, "TextDirection"))
        return g_variant_new_string("ltr");
      if (g_str_equal(property, "Status"))
        return g_variant_new_string("normal");
      return g_variant_new_strv(nullptr, 0);
    },
    nullptr,
    {nullptr}};

LinuxDesktopIntegration::LinuxDesktopIntegration(GtkWindow *window,
                                                 std::string config_directory,
                                                 std::string executable,
                                                 Action action)
    : window_(window),
      autostart_(std::move(config_directory), std::move(executable)),
      action_(std::move(action)), cancellable_(g_cancellable_new()),
      tray_info_(g_dbus_node_info_new_for_xml(kTrayXml, nullptr)),
      menu_info_(g_dbus_node_info_new_for_xml(kMenuXml, nullptr)),
      icon_pixmaps_(LoadPixmaps()),
      notification_icon_(gdk_pixbuf_new_from_resource_at_scale(
          "/dev/rainlink/rainlink/rainlink.png", 64, 64, TRUE, nullptr)) {
  if (window_ != nullptr) {
    g_object_add_weak_pointer(G_OBJECT(window_),
                              reinterpret_cast<gpointer *>(&window_));
  }
}

LinuxDesktopIntegration::~LinuxDesktopIntegration() {
  g_cancellable_cancel(cancellable_);
  if (bus_cancellable_ != nullptr)
    g_cancellable_cancel(bus_cancellable_);
  if (bus_timeout_ != 0)
    g_source_remove(bus_timeout_);
  ClearBus();
  if (popup_menu_ != nullptr) {
    gtk_widget_destroy(popup_menu_);
    g_object_unref(popup_menu_);
  }
  if (window_ != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(window_),
                                 reinterpret_cast<gpointer *>(&window_));
  }
  g_clear_object(&notification_icon_);
  g_clear_pointer(&icon_pixmaps_, g_variant_unref);
  g_clear_pointer(&tray_info_, g_dbus_node_info_unref);
  g_clear_pointer(&menu_info_, g_dbus_node_info_unref);
  g_clear_object(&bus_);
  g_clear_object(&bus_cancellable_);
  g_clear_object(&cancellable_);
}

void LinuxDesktopIntegration::ClearBus() {
  if (watcher_watch_ != 0)
    g_bus_unwatch_name(watcher_watch_);
  if (notifier_watch_ != 0)
    g_bus_unwatch_name(notifier_watch_);
  watcher_watch_ = notifier_watch_ = 0;
  RemoveTray();
  if (bus_ != nullptr) {
    for (guint subscription : {host_subscription_, host_event_subscription_,
                               notification_subscription_}) {
      if (subscription != 0)
        g_dbus_connection_signal_unsubscribe(bus_, subscription);
    }
    if (closed_handler_ != 0)
      g_signal_handler_disconnect(bus_, closed_handler_);
  }
  host_subscription_ = host_event_subscription_ = notification_subscription_ =
      0;
  closed_handler_ = 0;
  watcher_owner_.clear();
  g_clear_object(&bus_);
}

void LinuxDesktopIntegration::Emit(const char *action) {
  if (action_)
    action_(action);
}

void LinuxDesktopIntegration::EnsureBus(Reply reply) {
  if (bus_ != nullptr && !g_dbus_connection_is_closed(bus_)) {
    reply(nullptr);
    return;
  }
  // Do not spawn an ad-hoc session bus outside the user's desktop session.
  if (g_getenv("DBUS_SESSION_BUS_ADDRESS") == nullptr) {
    reply("desktop_bus_unavailable");
    return;
  }
  bus_waiters_.push_back(std::move(reply));
  if (bus_cancellable_ != nullptr)
    return;
  bus_cancellable_ = g_cancellable_new();
  bus_timeout_ = g_timeout_add_full(
      G_PRIORITY_DEFAULT, kBusTimeoutMs,
      [](gpointer data) -> gboolean {
        auto *self = static_cast<LinuxDesktopIntegration *>(data);
        self->bus_timeout_ = 0;
        g_cancellable_cancel(self->bus_cancellable_);
        return G_SOURCE_REMOVE;
      },
      this, nullptr);
  g_bus_get(
      G_BUS_TYPE_SESSION, bus_cancellable_,
      [](GObject *, GAsyncResult *result, gpointer data) {
        std::unique_ptr<std::weak_ptr<LinuxDesktopIntegration>> weak(
            static_cast<std::weak_ptr<LinuxDesktopIntegration> *>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(GDBusConnection) bus = g_bus_get_finish(result, &error);
        if (auto self = weak->lock())
          self->FinishBus(bus, error);
      },
      new std::weak_ptr<LinuxDesktopIntegration>(shared_from_this()));
}

void LinuxDesktopIntegration::FinishBus(GDBusConnection *bus,
                                        const GError *error) {
  if (bus_timeout_ != 0)
    g_source_remove(bus_timeout_);
  bus_timeout_ = 0;
  g_clear_object(&bus_cancellable_);
  if (bus != nullptr && error == nullptr) {
    ClearBus();
    bus_ = G_DBUS_CONNECTION(g_object_ref(bus));
    g_dbus_connection_set_exit_on_close(bus_, FALSE);
    closed_handler_ = g_signal_connect(
        bus_, "closed",
        G_CALLBACK(+[](GDBusConnection *, gboolean, GError *, gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          self->LostTray();
          self->notifications_available_ = false;
          self->ClearBus();
          self->Emit("capabilitiesChanged");
        }),
        this);
    watcher_watch_ = g_bus_watch_name_on_connection(
        bus_, kWatcher, G_BUS_NAME_WATCHER_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *owner,
           gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          if (self->watcher_owner_ != owner)
            self->LostTray();
          self->watcher_owner_ = owner;
          self->ProbeTray([weak = std::weak_ptr<LinuxDesktopIntegration>(
                               self->shared_from_this())](const char *) {
            if (auto current = weak.lock()) {
              if (current->tray_requested_ && current->host_available_) {
                current->RegisterTray([](const char *) {});
              }
              current->Emit("capabilitiesChanged");
            }
          });
        },
        [](GDBusConnection *, const gchar *, gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          self->LostTray();
          self->watcher_owner_.clear();
          self->Emit("capabilitiesChanged");
        },
        this, nullptr);
    notifier_watch_ = g_bus_watch_name_on_connection(
        bus_, kNotifications, G_BUS_NAME_WATCHER_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *, gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          self->notifications_available_ = true;
          self->Emit("capabilitiesChanged");
        },
        [](GDBusConnection *, const gchar *, gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          self->notifications_available_ = false;
          self->connection_notification_ = 0;
          self->expiry_notification_ = 0;
          self->Emit("capabilitiesChanged");
        },
        this, nullptr);
    host_subscription_ = g_dbus_connection_signal_subscribe(
        bus_, kWatcher, kProperties, "PropertiesChanged", kWatcherPath,
        kWatcher, G_DBUS_SIGNAL_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
           const gchar *, GVariant *, gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          self->ProbeTray([weak = std::weak_ptr<LinuxDesktopIntegration>(
                               self->shared_from_this())](const char *) {
            if (auto current = weak.lock()) {
              if (!current->host_available_)
                current->LostTray();
              current->Emit("capabilitiesChanged");
            }
          });
        },
        this, nullptr);
    host_event_subscription_ = g_dbus_connection_signal_subscribe(
        bus_, kWatcher, kWatcher, nullptr, kWatcherPath, nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
           const gchar *name, GVariant *, gpointer data) {
          if (!g_str_equal(name, "StatusNotifierHostRegistered") &&
              !g_str_equal(name, "StatusNotifierHostUnregistered"))
            return;
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          self->ProbeTray([weak = std::weak_ptr<LinuxDesktopIntegration>(
                               self->shared_from_this())](const char *) {
            if (auto current = weak.lock()) {
              if (!current->host_available_)
                current->LostTray();
              current->Emit("capabilitiesChanged");
            }
          });
        },
        this, nullptr);
    notification_subscription_ = g_dbus_connection_signal_subscribe(
        bus_, kNotifications, kNotifications, "ActionInvoked",
        kNotificationsPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
           const gchar *, GVariant *arguments, gpointer data) {
          auto *self = static_cast<LinuxDesktopIntegration *>(data);
          guint32 id = 0;
          const char *action = nullptr;
          g_variant_get(arguments, "(u&s)", &id, &action);
          if (id == 0 || !g_str_equal(action, "default"))
            return;
          if (id == self->expiry_notification_) {
            self->ShowWindow();
            self->Emit("showGroups");
          } else if (id == self->connection_notification_) {
            self->ShowWindow();
            self->Emit("show");
          }
        },
        this, nullptr);
  }
  auto waiters = std::move(bus_waiters_);
  bus_waiters_.clear();
  for (auto &waiter : waiters)
    waiter(error == nullptr && bus != nullptr ? nullptr
                                              : "desktop_bus_unavailable");
}

void LinuxDesktopIntegration::Call(const char *destination, const char *path,
                                   const char *interface, const char *method,
                                   GVariant *parameters,
                                   const GVariantType *response_type,
                                   BusReply reply) {
  auto *pending = new PendingCall{shared_from_this(), std::move(reply)};
  g_dbus_connection_call(
      bus_, destination, path, interface, method, parameters, response_type,
      G_DBUS_CALL_FLAGS_NO_AUTO_START, kBusTimeoutMs, cancellable_,
      [](GObject *source, GAsyncResult *result, gpointer data) {
        std::unique_ptr<PendingCall> pending(static_cast<PendingCall *>(data));
        g_autoptr(GError) error = nullptr;
        g_autoptr(GVariant) value = g_dbus_connection_call_finish(
            G_DBUS_CONNECTION(source), result, &error);
        if (auto owner = pending->owner.lock())
          pending->reply(value, error);
      },
      pending);
}

void LinuxDesktopIntegration::ProbeTray(Reply reply) {
  Call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
       "GetNameOwner", g_variant_new("(s)", kWatcher), G_VARIANT_TYPE("(s)"),
       [this, reply = std::move(reply)](GVariant *value, const GError *error) {
         if (error != nullptr) {
           host_available_ = false;
           reply("tray_unavailable");
           return;
         }
         const char *owner = nullptr;
         g_variant_get(value, "(&s)", &owner);
         const std::string expected_owner(owner);
         if (watcher_owner_ != owner)
           LostTray();
         watcher_owner_ = owner;
         Call(owner, kWatcherPath, kProperties, "Get",
              g_variant_new("(ss)", kWatcher, "IsStatusNotifierHostRegistered"),
              G_VARIANT_TYPE("(v)"),
              [this, expected_owner, reply](GVariant *result,
                                            const GError *failure) {
                bool available = false;
                if (failure == nullptr && watcher_owner_ == expected_owner) {
                  g_autoptr(GVariant) wrapped =
                      g_variant_get_child_value(result, 0);
                  g_autoptr(GVariant) field = g_variant_get_variant(wrapped);
                  available =
                      g_variant_is_of_type(field, G_VARIANT_TYPE_BOOLEAN) &&
                      g_variant_get_boolean(field);
                }
                host_available_ = available;
                reply(available ? nullptr : "tray_unavailable");
              });
       });
}

void LinuxDesktopIntegration::Inspect(StatusReply reply) {
  bool launch = false;
  g_autoptr(GError) error = nullptr;
  if (!autostart_.Read(&launch, &error)) {
    reply({}, "startup_read_failed");
    return;
  }
  EnsureBus([this, launch, reply](const char *failure) {
    if (failure != nullptr) {
      reply({launch, false, false, false}, nullptr);
      return;
    }
    ProbeTray([this, launch, reply](const char *) {
      Call("org.freedesktop.DBus", "/org/freedesktop/DBus",
           "org.freedesktop.DBus", "NameHasOwner",
           g_variant_new("(s)", kNotifications), G_VARIANT_TYPE("(b)"),
           [this, launch, reply](GVariant *result, const GError *error) {
             gboolean available = FALSE;
             if (error == nullptr)
               g_variant_get(result, "(b)", &available);
             notifications_available_ = available;
             reply({launch, tray_visible_ && host_available_, host_available_,
                    notifications_available_},
                   nullptr);
           });
    });
  });
}

void LinuxDesktopIntegration::SetLaunchAtLogin(bool enabled, Reply reply) {
  g_autoptr(GError) error = nullptr;
  if (autostart_.Write(enabled, &error)) {
    reply(nullptr);
  } else {
    reply(g_error_matches(error, G_IO_ERROR, G_IO_ERROR_EXISTS)
              ? "startup_conflict"
              : "startup_write_failed");
  }
}

void LinuxDesktopIntegration::SetTrayVisible(bool visible, Reply reply) {
  const auto request = ++tray_request_generation_;
  if (!visible) {
    ++tray_generation_;
    tray_requested_ = false;
    if (tray_visible_)
      ShowWindow();
    tray_visible_ = false;
    RemoveTray();
    CompleteRegistration("tray_registration_cancelled");
    reply(nullptr);
    return;
  }
  EnsureBus([this, request, reply](const char *error) {
    // A later hide request owns the final state even while the bus or watcher
    // is still being probed. Never recreate an icon after acknowledging hide.
    if (request != tray_request_generation_) {
      reply("tray_registration_cancelled");
      return;
    }
    if (error != nullptr) {
      reply(error);
      return;
    }
    ProbeTray([this, request, reply](const char *failure) {
      if (request != tray_request_generation_) {
        reply("tray_registration_cancelled");
        return;
      }
      if (failure != nullptr) {
        reply(failure);
        return;
      }
      RegisterTray(reply);
    });
  });
}

void LinuxDesktopIntegration::RegisterTray(Reply reply) {
  if (tray_visible_) {
    tray_requested_ = true;
    reply(nullptr);
    return;
  }
  if (g_variant_n_children(icon_pixmaps_) == 0) {
    reply("tray_icon_unavailable");
    return;
  }
  registration_waiters_.push_back(std::move(reply));
  if (tray_name_owner_ != 0)
    return;
  g_autoptr(GError) error = nullptr;
  if (tray_registration_ == 0) {
    tray_registration_ = g_dbus_connection_register_object(
        bus_, kTrayPath, tray_info_->interfaces[0], &kTrayVtable, this, nullptr,
        &error);
  }
  if (error == nullptr && menu_registration_ == 0) {
    menu_registration_ = g_dbus_connection_register_object(
        bus_, kMenuPath, menu_info_->interfaces[0], &kMenuVtable, this, nullptr,
        &error);
  }
  if (error != nullptr) {
    RemoveTray();
    CompleteRegistration("tray_registration_failed");
    return;
  }
  ++tray_generation_;
  const std::string service =
      "org.kde.StatusNotifierItem-" + std::to_string(getpid()) + "-1";
  tray_name_owner_ = g_bus_own_name_on_connection(
      bus_, service.c_str(), G_BUS_NAME_OWNER_FLAGS_DO_NOT_QUEUE,
      [](GDBusConnection *, const gchar *name, gpointer data) {
        auto *self = static_cast<LinuxDesktopIntegration *>(data);
        const auto generation = self->tray_generation_;
        const std::string owner = self->watcher_owner_;
        self->Call(
            owner.c_str(), kWatcherPath, kWatcher, "RegisterStatusNotifierItem",
            g_variant_new("(s)", name), G_VARIANT_TYPE("()"),
            [self, generation, owner](GVariant *, const GError *failure) {
              if (generation != self->tray_generation_ ||
                  owner != self->watcher_owner_)
                return;
              self->tray_visible_ = failure == nullptr && self->host_available_;
              if (!self->tray_visible_) {
                self->RemoveTray();
                self->CompleteRegistration("tray_registration_failed");
                return;
              }
              self->tray_requested_ = true;
              self->CompleteRegistration(nullptr);
            });
      },
      [](GDBusConnection *, const gchar *, gpointer data) {
        auto *self = static_cast<LinuxDesktopIntegration *>(data);
        self->LostTray();
        self->RemoveTray();
        self->CompleteRegistration("tray_registration_failed");
      },
      this, nullptr);
}

void LinuxDesktopIntegration::CompleteRegistration(const char *error_code) {
  auto waiters = std::move(registration_waiters_);
  registration_waiters_.clear();
  for (auto &waiter : waiters)
    waiter(error_code);
}

void LinuxDesktopIntegration::RemoveTray() {
  if (tray_name_owner_ != 0)
    g_bus_unown_name(tray_name_owner_);
  tray_name_owner_ = 0;
  if (bus_ != nullptr) {
    if (tray_registration_ != 0) {
      g_dbus_connection_unregister_object(bus_, tray_registration_);
    }
    if (menu_registration_ != 0) {
      g_dbus_connection_unregister_object(bus_, menu_registration_);
    }
  }
  tray_registration_ = 0;
  menu_registration_ = 0;
}

void LinuxDesktopIntegration::LostTray() {
  ++tray_generation_;
  const bool restore = tray_visible_;
  tray_visible_ = false;
  host_available_ = false;
  RemoveTray();
  CompleteRegistration("tray_registration_cancelled");
  if (restore) {
    ShowWindow();
    Emit("show");
  }
}

void LinuxDesktopIntegration::UpdateTray(std::string label,
                                         std::string action_label, bool busy) {
  label_ = std::move(label);
  action_label_ = std::move(action_label);
  busy_ = busy;
  if (bus_ == nullptr || !tray_visible_)
    return;
  g_dbus_connection_emit_signal(bus_, nullptr, kTrayPath, kTrayInterface,
                                "NewToolTip", nullptr, nullptr);
  g_dbus_connection_emit_signal(
      bus_, nullptr, kMenuPath, kMenuInterface, "LayoutUpdated",
      g_variant_new("(ui)", ++menu_revision_, 0), nullptr);
}

void LinuxDesktopIntegration::ShowWindow() {
  if (window_ == nullptr)
    return;
  gtk_widget_show(GTK_WIDGET(window_));
  gtk_window_deiconify(window_);
  gtk_window_present(window_);
}

void LinuxDesktopIntegration::HideWindow(Reply reply) {
  EnsureBus([this, reply](const char *failure) {
    if (failure != nullptr) {
      ShowWindow();
      reply(failure);
      return;
    }
    ProbeTray([this, reply](const char *error) {
      if (error != nullptr || !tray_visible_ || window_ == nullptr) {
        ShowWindow();
        reply("tray_unavailable");
        return;
      }
      gtk_widget_hide(GTK_WIDGET(window_));
      reply(nullptr);
    });
  });
}

GVariant *LinuxDesktopIntegration::TrayProperty(const char *property) const {
  if (g_str_equal(property, "Category"))
    return g_variant_new_string("Communications");
  if (g_str_equal(property, "Id"))
    return g_variant_new_string("dev.rainlink.rainlink");
  if (g_str_equal(property, "Title"))
    return g_variant_new_string("RainLink");
  if (g_str_equal(property, "Status"))
    return g_variant_new_string("Active");
  if (g_str_equal(property, "WindowId"))
    return g_variant_new_uint32(0);
  if (g_str_equal(property, "IconPixmap"))
    return g_variant_ref(icon_pixmaps_);
  if (g_str_equal(property, "OverlayIconPixmap") ||
      g_str_equal(property, "AttentionIconPixmap"))
    return EmptyPixmaps();
  if (g_str_equal(property, "ItemIsMenu"))
    return g_variant_new_boolean(FALSE);
  if (g_str_equal(property, "Menu"))
    return g_variant_new_object_path(kMenuPath);
  if (g_str_equal(property, "ToolTip")) {
    return g_variant_new("(s@a(iiay)ss)", "", g_variant_ref(icon_pixmaps_),
                         "RainLink", label_.c_str());
  }
  return g_variant_new_string("");
}

void LinuxDesktopIntegration::TrayMethod(const char *method,
                                         GVariant *arguments,
                                         GDBusMethodInvocation *invocation) {
  if (g_str_equal(method, "ContextMenu")) {
    gint32 x, y;
    g_variant_get(arguments, "(ii)", &x, &y);
    PopupMenu(x, y);
  } else if (g_str_equal(method, "Activate") ||
             g_str_equal(method, "SecondaryActivate")) {
    ShowWindow();
    Emit("show");
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

GVariant *LinuxDesktopIntegration::MenuProperties(int32_t id) const {
  GVariantBuilder properties;
  g_variant_builder_init(&properties, G_VARIANT_TYPE_VARDICT);
  if (id == 0) {
    g_variant_builder_add(&properties, "{sv}", "children-display",
                          g_variant_new_string("submenu"));
  } else if (id == 3) {
    g_variant_builder_add(&properties, "{sv}", "type",
                          g_variant_new_string("separator"));
  } else {
    const char *label = id == 1   ? "显示 RainLink"
                        : id == 2 ? action_label_.c_str()
                                  : "退出 RainLink";
    g_variant_builder_add(&properties, "{sv}", "label",
                          g_variant_new_string(label));
    g_variant_builder_add(&properties, "{sv}", "enabled",
                          g_variant_new_boolean(id != 2 || !busy_));
    g_variant_builder_add(&properties, "{sv}", "visible",
                          g_variant_new_boolean(TRUE));
  }
  return g_variant_builder_end(&properties);
}

GVariant *LinuxDesktopIntegration::MenuLayout(int32_t id, int32_t depth) const {
  GVariantBuilder children;
  g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
  if (id == 0 && depth != 0) {
    for (int child : {1, 2, 3, 4}) {
      g_variant_builder_add(&children, "v", MenuLayout(child, depth - 1));
    }
  }
  return g_variant_new("(i@a{sv}@av)", id, MenuProperties(id),
                       g_variant_builder_end(&children));
}

void LinuxDesktopIntegration::MenuAction(int32_t id) {
  if (id == 1) {
    ShowWindow();
    Emit("show");
  } else if (id == 2 && !busy_) {
    Emit("toggleConnection");
  } else if (id == 4) {
    Emit("quit");
  }
}

void LinuxDesktopIntegration::MenuMethod(const char *method,
                                         GVariant *arguments,
                                         GDBusMethodInvocation *invocation) {
  if (g_str_equal(method, "GetLayout")) {
    gint32 parent = 0, depth = 0;
    g_autoptr(GVariant) names = nullptr;
    g_variant_get(arguments, "(ii@as)", &parent, &depth, &names);
    if (KnownMenuId(parent)) {
      g_dbus_method_invocation_return_value(
          invocation, g_variant_new("(u@(ia{sv}av))", menu_revision_,
                                    MenuLayout(parent, depth)));
      return;
    }
  } else if (g_str_equal(method, "GetGroupProperties")) {
    g_autoptr(GVariant) ids = g_variant_get_child_value(arguments, 0);
    GVariantBuilder result;
    g_variant_builder_init(&result, G_VARIANT_TYPE("a(ia{sv})"));
    GVariantIter iterator;
    g_variant_iter_init(&iterator, ids);
    gint32 id;
    if (g_variant_n_children(ids) == 0) {
      for (int item : {0, 1, 2, 3, 4}) {
        g_variant_builder_add(&result, "(i@a{sv})", item, MenuProperties(item));
      }
    } else {
      while (g_variant_iter_next(&iterator, "i", &id)) {
        if (KnownMenuId(id)) {
          g_variant_builder_add(&result, "(i@a{sv})", id, MenuProperties(id));
        }
      }
    }
    g_dbus_method_invocation_return_value(
        invocation,
        g_variant_new("(@a(ia{sv}))", g_variant_builder_end(&result)));
    return;
  } else if (g_str_equal(method, "GetProperty")) {
    gint32 id;
    const char *name;
    g_variant_get(arguments, "(i&s)", &id, &name);
    g_autoptr(GVariant) properties =
        KnownMenuId(id) ? g_variant_ref_sink(MenuProperties(id)) : nullptr;
    g_autoptr(GVariant) property =
        properties != nullptr
            ? g_variant_lookup_value(properties, name, nullptr)
            : nullptr;
    if (property != nullptr) {
      g_dbus_method_invocation_return_value(invocation,
                                            g_variant_new("(v)", property));
      return;
    }
  } else if (g_str_equal(method, "Event")) {
    gint32 id;
    const char *event;
    g_autoptr(GVariant) data = nullptr;
    guint32 timestamp;
    g_variant_get(arguments, "(i&s@vu)", &id, &event, &data, &timestamp);
    if (KnownMenuId(id)) {
      if (g_str_equal(event, "clicked"))
        MenuAction(id);
      g_dbus_method_invocation_return_value(invocation, nullptr);
      return;
    }
  } else if (g_str_equal(method, "EventGroup")) {
    g_autoptr(GVariant) events = g_variant_get_child_value(arguments, 0);
    GVariantBuilder failures;
    g_variant_builder_init(&failures, G_VARIANT_TYPE("ai"));
    for (gsize index = 0; index < g_variant_n_children(events); ++index) {
      g_autoptr(GVariant) event = g_variant_get_child_value(events, index);
      gint32 id;
      const char *name;
      g_autoptr(GVariant) data = nullptr;
      guint32 timestamp;
      g_variant_get(event, "(i&s@vu)", &id, &name, &data, &timestamp);
      if (!KnownMenuId(id))
        g_variant_builder_add(&failures, "i", id);
      else if (g_str_equal(name, "clicked"))
        MenuAction(id);
    }
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(@ai)", g_variant_builder_end(&failures)));
    return;
  } else if (g_str_equal(method, "AboutToShow")) {
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(b)", FALSE));
    return;
  } else if (g_str_equal(method, "AboutToShowGroup")) {
    g_dbus_method_invocation_return_value(
        invocation,
        g_variant_new("(@ai@ai)",
                      g_variant_new_array(G_VARIANT_TYPE_INT32, nullptr, 0),
                      g_variant_new_array(G_VARIANT_TYPE_INT32, nullptr, 0)));
    return;
  }
  g_dbus_method_invocation_return_dbus_error(
      invocation, "org.freedesktop.DBus.Error.InvalidArgs",
      "Unknown menu item or property");
}

void LinuxDesktopIntegration::PopupMenu(int32_t x, int32_t y) {
  if (window_ == nullptr)
    return;
  if (popup_menu_ != nullptr) {
    gtk_widget_destroy(popup_menu_);
    g_object_unref(popup_menu_);
  }
  popup_menu_ = gtk_menu_new();
  g_object_ref_sink(popup_menu_);
  for (int id : {1, 2, 3, 4}) {
    const char *label = id == 1   ? "显示 RainLink"
                        : id == 2 ? action_label_.c_str()
                                  : "退出 RainLink";
    GtkWidget *item = id == 3 ? gtk_separator_menu_item_new()
                              : gtk_menu_item_new_with_label(label);
    gtk_widget_set_sensitive(item, id != 2 || !busy_);
    g_object_set_data(G_OBJECT(item), "rainlink-id", GINT_TO_POINTER(id));
    g_signal_connect(item, "activate",
                     G_CALLBACK(+[](GtkMenuItem *menu_item, gpointer data) {
                       static_cast<LinuxDesktopIntegration *>(data)->MenuAction(
                           GPOINTER_TO_INT(g_object_get_data(
                               G_OBJECT(menu_item), "rainlink-id")));
                     }),
                     this);
    gtk_menu_shell_append(GTK_MENU_SHELL(popup_menu_), item);
  }
  gtk_widget_show_all(popup_menu_);
  const GdkRectangle anchor{x, y, 1, 1};
  gtk_menu_popup_at_rect(GTK_MENU(popup_menu_), gdk_get_default_root_window(),
                         &anchor, GDK_GRAVITY_SOUTH_WEST,
                         GDK_GRAVITY_NORTH_WEST, nullptr);
}

void LinuxDesktopIntegration::NotifyConnection(const std::string &message,
                                               Reply reply) {
  Notify("RainLink", message, false, std::move(reply));
}

void LinuxDesktopIntegration::NotifySubscriptionExpiry(int32_t soon,
                                                       int32_t expired,
                                                       Reply reply) {
  if (soon < 0 || expired < 0 || (soon == 0 && expired == 0)) {
    reply("invalid_arguments");
    return;
  }
  std::string message;
  if (expired > 0)
    message = std::to_string(expired) + " 个订阅已到期";
  if (soon > 0) {
    if (!message.empty())
      message += "；";
    message += std::to_string(soon) + " 个订阅将在 3 天内到期";
  }
  Notify("RainLink · 订阅到期提醒", message + "。请到「分组」查看。", true,
         std::move(reply));
}

void LinuxDesktopIntegration::Notify(const std::string &title,
                                     const std::string &message, bool expiry,
                                     Reply reply) {
  EnsureBus([this, title, message, expiry, reply](const char *error) {
    if (error != nullptr) {
      reply(error);
      return;
    }
    GVariantBuilder hints;
    g_variant_builder_init(&hints, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&hints, "{sv}", "desktop-entry",
                          g_variant_new_string("dev.rainlink.rainlink"));
    g_variant_builder_add(&hints, "{sv}", "category",
                          g_variant_new_string("network"));
    g_variant_builder_add(&hints, "{sv}", "suppress-sound",
                          g_variant_new_boolean(TRUE));
    if (notification_icon_ != nullptr) {
      const int width = gdk_pixbuf_get_width(notification_icon_);
      const int height = gdk_pixbuf_get_height(notification_icon_);
      const int stride = gdk_pixbuf_get_rowstride(notification_icon_);
      const int channels = gdk_pixbuf_get_n_channels(notification_icon_);
      const guchar *bytes = gdk_pixbuf_read_pixels(notification_icon_);
      GVariant *pixels = g_variant_new_fixed_array(
          G_VARIANT_TYPE_BYTE, bytes,
          gdk_pixbuf_get_byte_length(notification_icon_), 1);
      g_variant_builder_add(
          &hints, "{sv}", "image-data",
          g_variant_new("(iiibii@ay)", width, height, stride,
                        gdk_pixbuf_get_has_alpha(notification_icon_), 8,
                        channels, pixels));
    }
    const char *actions[] = {"default", expiry ? "查看分组" : "显示 RainLink"};
    g_autofree gchar *escaped = g_markup_escape_text(message.c_str(), -1);
    Call(kNotifications, kNotificationsPath, kNotifications, "Notify",
         g_variant_new("(susss@as@a{sv}i)", "RainLink",
                       expiry ? expiry_notification_ : connection_notification_,
                       "", title.c_str(), escaped,
                       g_variant_new_strv(actions, 2),
                       g_variant_builder_end(&hints), 5000),
         G_VARIANT_TYPE("(u)"),
         [this, expiry, reply](GVariant *result, const GError *failure) {
           guint32 id = 0;
           if (failure == nullptr)
             g_variant_get(result, "(u)", &id);
           if (id == 0) {
             reply("notifications_unavailable");
             return;
           }
           if (expiry)
             expiry_notification_ = id;
           else
             connection_notification_ = id;
           reply(nullptr);
         });
  });
}
