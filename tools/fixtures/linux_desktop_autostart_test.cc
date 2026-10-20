#include "desktop_autostart.h"

#include <gio/gdesktopappinfo.h>
#include <glib/gstdio.h>
#include <sys/stat.h>

#include <string>

namespace {
std::string TemporaryDirectory() {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar *path = g_dir_make_tmp("rainlink-autostart-XXXXXX", &error);
  g_assert_no_error(error);
  return path;
}

std::string ReadFile(const std::string &path) {
  g_autofree gchar *value = nullptr;
  g_autoptr(GError) error = nullptr;
  g_assert_true(g_file_get_contents(path.c_str(), &value, nullptr, &error));
  g_assert_no_error(error);
  return value;
}

void LaunchEscapedExecutable() {
  const auto root = TemporaryDirectory();
  const auto executable = root + "/Rain Link % \" $ ` \\";
  const auto receipt = root + "/receipt";
  g_autofree gchar *quoted = g_shell_quote(receipt.c_str());
  const auto script =
      std::string("#!/bin/sh\nprintf '%s\\n' \"$@\" > ") + quoted + "\n";
  g_assert_true(
      g_file_set_contents(executable.c_str(), script.c_str(), -1, nullptr));
  g_assert_cmpint(g_chmod(executable.c_str(), 0700), ==, 0);
  DesktopAutostart settings(root, executable);
  g_autoptr(GError) error = nullptr;
  g_assert_true(settings.Write(true, &error));
  g_assert_no_error(error);
  bool enabled = false;
  g_assert_true(settings.Read(&enabled, &error));
  g_assert_true(enabled);
  const auto entry = root + "/autostart/dev.rainlink.rainlink.desktop";
  g_autoptr(GDesktopAppInfo) launch =
      g_desktop_app_info_new_from_filename(entry.c_str());
  g_assert_nonnull(launch);
  g_assert_true(
      g_app_info_launch(G_APP_INFO(launch), nullptr, nullptr, &error));
  g_assert_no_error(error);
  for (int attempt = 0;
       attempt < 100 && !g_file_test(receipt.c_str(), G_FILE_TEST_EXISTS);
       ++attempt) {
    g_usleep(10000);
  }
  g_assert_true(ReadFile(receipt) == "--autostart\n");
  struct stat info;
  g_assert_cmpint(g_stat(entry.c_str(), &info), ==, 0);
  g_assert_cmpint(info.st_mode & 0777, ==, 0600);
  g_assert_true(settings.Write(false, &error));
  g_assert_no_error(error);
  g_assert_false(g_file_test(entry.c_str(), G_FILE_TEST_EXISTS));
}

void OtherInstallationIsPreserved() {
  const auto root = TemporaryDirectory();
  DesktopAutostart first(root, "/opt/rainlink/one/rainlink");
  DesktopAutostart second(root, "/opt/rainlink/two/rainlink");
  g_autoptr(GError) error = nullptr;
  g_assert_true(first.Write(true, &error));
  const auto entry = root + "/autostart/dev.rainlink.rainlink.desktop";
  const auto original = ReadFile(entry);
  bool enabled = true;
  g_assert_true(second.Read(&enabled, &error));
  g_assert_false(enabled);
  g_assert_true(second.Write(false, &error));
  g_assert_true(ReadFile(entry) == original);
  g_assert_false(second.Write(true, &error));
  g_assert_error(error, G_IO_ERROR, G_IO_ERROR_EXISTS);
  g_clear_error(&error);
  g_assert_true(ReadFile(entry) == original);
  g_assert_true(first.Write(false, &error));
}

void ForeignAndSymlinkEntriesArePreserved() {
  for (bool symlink : {false, true}) {
    const auto root = TemporaryDirectory();
    const auto directory = root + "/autostart";
    const auto entry = directory + "/dev.rainlink.rainlink.desktop";
    const auto foreign = root + "/foreign";
    g_assert_cmpint(g_mkdir(directory.c_str(), 0700), ==, 0);
    g_assert_true(
        g_file_set_contents(foreign.c_str(), "foreign contents", -1, nullptr));
    if (symlink) {
      g_autoptr(GFile) file = g_file_new_for_path(entry.c_str());
      g_assert_true(
          g_file_make_symbolic_link(file, foreign.c_str(), nullptr, nullptr));
    } else {
      g_assert_true(g_file_set_contents(entry.c_str(), "invalid desktop entry",
                                        -1, nullptr));
    }
    const auto original = ReadFile(entry);
    DesktopAutostart settings(root, "/opt/rainlink/rainlink");
    g_autoptr(GError) error = nullptr;
    bool enabled = true;
    g_assert_true(settings.Read(&enabled, &error));
    g_assert_false(enabled);
    g_assert_true(settings.Write(false, &error));
    g_assert_false(settings.Write(true, &error));
    g_assert_error(error, G_IO_ERROR, G_IO_ERROR_EXISTS);
    g_assert_true(ReadFile(entry) == original);
    g_assert_true(ReadFile(foreign) == "foreign contents");
  }
}

void DisabledEntryCanBeEnabledAgain() {
  const auto root = TemporaryDirectory();
  DesktopAutostart settings(root, "/opt/rainlink/rainlink");
  g_autoptr(GError) error = nullptr;
  g_assert_true(settings.Write(true, &error));
  const auto entry = root + "/autostart/dev.rainlink.rainlink.desktop";
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_assert_true(g_key_file_load_from_file(key_file, entry.c_str(),
                                          G_KEY_FILE_NONE, &error));
  g_key_file_set_boolean(key_file, G_KEY_FILE_DESKTOP_GROUP, "Hidden", TRUE);
  g_assert_true(g_key_file_save_to_file(key_file, entry.c_str(), &error));
  bool enabled = true;
  g_assert_true(settings.Read(&enabled, &error));
  g_assert_false(enabled);
  g_assert_true(settings.Write(true, &error));
  g_assert_true(settings.Read(&enabled, &error));
  g_assert_true(enabled);
  g_assert_true(settings.Write(false, &error));
  g_assert_no_error(error);
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/autostart/exec-desktop-parser-and-spawn",
                  LaunchEscapedExecutable);
  g_test_add_func("/autostart/other-installation",
                  OtherInstallationIsPreserved);
  g_test_add_func("/autostart/foreign-and-symlink",
                  ForeignAndSymlinkEntriesArePreserved);
  g_test_add_func("/autostart/disabled-entry", DisabledEntryCanBeEnabledAgain);
  return g_test_run();
}
