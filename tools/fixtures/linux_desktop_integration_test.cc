#include "desktop_integration.h"

#include <unistd.h>

#include <functional>
#include <memory>
#include <string>

namespace {
using Desktop = std::shared_ptr<LinuxDesktopIntegration>;

void WaitFor(const std::function<bool()> &completed) {
  const gint64 deadline = g_get_monotonic_time() + 5 * G_TIME_SPAN_SECOND;
  while (!completed() && g_get_monotonic_time() < deadline) {
    g_main_context_iteration(nullptr, FALSE);
    g_usleep(1000);
  }
  g_assert_true(completed());
}

Desktop Create() {
  return std::make_shared<LinuxDesktopIntegration>(
      nullptr, "/tmp/rainlink-desktop-native-tests", "/usr/bin/true",
      [](const std::string &) {});
}

LinuxDesktopStatus Inspect(const Desktop &desktop) {
  bool completed = false;
  LinuxDesktopStatus observed;
  desktop->Inspect([&](const LinuxDesktopStatus &status, const char *error) {
    g_assert_null(error);
    observed = status;
    completed = true;
  });
  WaitFor([&] { return completed; });
  return observed;
}

bool OwnsTrayName() {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  g_assert_no_error(error);
  const std::string name =
      "org.kde.StatusNotifierItem-" + std::to_string(getpid()) + "-1";
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", name.c_str()), G_VARIANT_TYPE("(b)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_assert_no_error(error);
  gboolean owned = FALSE;
  g_variant_get(result, "(b)", &owned);
  return owned;
}

bool WatcherContainsTray() {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  g_assert_no_error(error);
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.kde.StatusNotifierWatcher",
                    "RegisteredStatusNotifierItems"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_assert_no_error(error);
  g_autoptr(GVariant) wrapped = g_variant_get_child_value(result, 0);
  g_autoptr(GVariant) items = g_variant_get_variant(wrapped);
  const std::string service =
      "org.kde.StatusNotifierItem-" + std::to_string(getpid()) + "-1";
  GVariantIter iterator;
  g_variant_iter_init(&iterator, items);
  const char *name = nullptr;
  while (g_variant_iter_next(&iterator, "&s", &name)) {
    if (std::string(name).find(service) != std::string::npos)
      return true;
  }
  return false;
}

void OffCancelsPendingEnable() {
  auto desktop = Create();
  g_assert_true(Inspect(desktop).tray_available);
  bool enabled_complete = false;
  bool disabled_complete = false;
  std::string enable_error;
  desktop->SetTrayVisible(true, [&](const char *error) {
    enable_error = error != nullptr ? error : "";
    enabled_complete = true;
  });
  desktop->SetTrayVisible(false, [&](const char *error) {
    g_assert_null(error);
    disabled_complete = true;
  });
  WaitFor([&] { return enabled_complete && disabled_complete; });
  g_assert_cmpstr(enable_error.c_str(), ==, "tray_registration_cancelled");
  g_assert_false(Inspect(desktop).tray_visible);
  WaitFor([] { return !OwnsTrayName(); });
}

void ReleaseDoesNotLeaveGhostItem() {
  auto desktop = Create();
  bool completed = false;
  desktop->SetTrayVisible(true, [&](const char *error) {
    g_assert_null(error);
    completed = true;
  });
  WaitFor([&] { return completed; });
  g_assert_true(Inspect(desktop).tray_visible);
  g_assert_true(OwnsTrayName());
  g_assert_true(WatcherContainsTray());
  desktop.reset();
  WaitFor([] { return !OwnsTrayName(); });
  WaitFor([] { return !WatcherContainsTray(); });
}

void DestructionDuringBusRequest() {
  for (int attempt = 0; attempt < 20; ++attempt) {
    auto desktop = Create();
    desktop->SetTrayVisible(true, [](const char *) {});
    desktop.reset();
    const gint64 until = g_get_monotonic_time() + 10000;
    while (g_get_monotonic_time() < until) {
      g_main_context_iteration(nullptr, FALSE);
      g_usleep(1000);
    }
  }
  WaitFor([] { return !OwnsTrayName(); });
}

void NoSessionBusIsReportedWithoutAutolaunch() {
  g_assert_null(g_getenv("DBUS_SESSION_BUS_ADDRESS"));
  auto desktop = Create();
  const auto observed = Inspect(desktop);
  g_assert_false(observed.tray_available);
  g_assert_false(observed.tray_visible);
  g_assert_false(observed.notifications_available);
  bool completed = false;
  desktop->SetTrayVisible(true, [&](const char *error) {
    g_assert_cmpstr(error, ==, "desktop_bus_unavailable");
    completed = true;
  });
  WaitFor([&] { return completed; });
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  if (g_getenv("DBUS_SESSION_BUS_ADDRESS") == nullptr) {
    g_test_add_func("/desktop/no-session-bus",
                    NoSessionBusIsReportedWithoutAutolaunch);
  } else {
    g_test_add_func("/desktop/off-cancels-pending-enable",
                    OffCancelsPendingEnable);
    g_test_add_func("/desktop/release-removes-item",
                    ReleaseDoesNotLeaveGhostItem);
    g_test_add_func("/desktop/destroy-pending-bus-request",
                    DestructionDuringBusRequest);
  }
  return g_test_run();
}
