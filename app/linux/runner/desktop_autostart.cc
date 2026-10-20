#include "desktop_autostart.h"

#include <fcntl.h>
#include <glib/gstdio.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <utility>
#include <vector>

namespace {
constexpr gsize kMaximumEntryBytes = 64 * 1024;
constexpr char kEntryName[] = "dev.rainlink.rainlink.desktop";
constexpr char kGroup[] = G_KEY_FILE_DESKTOP_GROUP;
constexpr char kOwnerKey[] = "X-RainLink-Executable";
constexpr char kVersionKey[] = "X-RainLink-Autostart-Version";
constexpr char kEnvExecutable[] = "/usr/bin/env";

bool FileError(GError **error, const char *operation) {
  g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno), "%s: %s",
              operation, g_strerror(errno));
  return false;
}

bool SameString(GKeyFile *file, const char *key, const std::string &expected) {
  g_autofree gchar *actual = g_key_file_get_string(file, kGroup, key, nullptr);
  return actual != nullptr && expected == actual;
}
} // namespace

struct DesktopAutostart::Entry {
  bool exists = false;
  bool owned = false;
  bool enabled = false;
  std::string etag;
};

DesktopAutostart::DesktopAutostart(std::string config_directory,
                                   std::string executable)
    : directory_(std::move(config_directory) + "/autostart"),
      path_(directory_ + "/" + kEntryName), executable_(std::move(executable)) {
}

std::string DesktopAutostart::Command() const {
  // Exec has its own quoting rules, then GKeyFile escapes the complete value.
  // Percent signs must be doubled so a path cannot introduce field codes.
  std::string result = "\"";
  for (char character : executable_) {
    if (character == '%') {
      result += "%%";
    } else {
      if (character == '\\' || character == '"' || character == '$' ||
          character == '`') {
        result += '\\';
      }
      result += character;
    }
  }
  // GIO checks the first executable before expanding %% field escapes. Use a
  // fixed executable and a quoted argument so percent-containing paths also
  // pass that check. env execs RainLink directly, without an intervening shell.
  return std::string("\"") + kEnvExecutable + "\" -- " + result +
         "\" --autostart";
}

std::string DesktopAutostart::Contents() const {
  g_autoptr(GKeyFile) entry = g_key_file_new();
  g_key_file_set_string(entry, kGroup, G_KEY_FILE_DESKTOP_KEY_TYPE,
                        G_KEY_FILE_DESKTOP_TYPE_APPLICATION);
  g_key_file_set_string(entry, kGroup, G_KEY_FILE_DESKTOP_KEY_NAME, "RainLink");
  g_key_file_set_string(entry, kGroup, G_KEY_FILE_DESKTOP_KEY_EXEC,
                        Command().c_str());
  g_key_file_set_string(entry, kGroup, G_KEY_FILE_DESKTOP_KEY_TRY_EXEC,
                        executable_.c_str());
  g_key_file_set_boolean(entry, kGroup, G_KEY_FILE_DESKTOP_KEY_TERMINAL, FALSE);
  g_key_file_set_boolean(entry, kGroup, G_KEY_FILE_DESKTOP_KEY_HIDDEN, FALSE);
  g_key_file_set_boolean(entry, kGroup, "X-GNOME-Autostart-enabled", TRUE);
  g_key_file_set_integer(entry, kGroup, kVersionKey, 1);
  g_key_file_set_string(entry, kGroup, kOwnerKey, executable_.c_str());
  g_autofree gchar *data = g_key_file_to_data(entry, nullptr, nullptr);
  return data;
}

bool DesktopAutostart::Inspect(Entry *entry, GError **error) const {
  if (!g_path_is_absolute(directory_.c_str()) ||
      !g_path_is_absolute(executable_.c_str()) ||
      executable_.find('\n') != std::string::npos ||
      executable_.find('\r') != std::string::npos ||
      !g_file_test(kEnvExecutable, G_FILE_TEST_IS_EXECUTABLE)) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                        "Invalid autostart directory or executable");
    return false;
  }
  g_autoptr(GFile) file = g_file_new_for_path(path_.c_str());
  g_autoptr(GError) query_error = nullptr;
  g_autoptr(GFileInfo) info = g_file_query_info(
      file,
      G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE
                                     "," G_FILE_ATTRIBUTE_ETAG_VALUE,
      G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, &query_error);
  if (info == nullptr) {
    if (g_error_matches(query_error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND)) {
      return true;
    }
    g_propagate_error(error, g_steal_pointer(&query_error));
    return false;
  }
  entry->exists = true;
  if (g_file_info_get_file_type(info) != G_FILE_TYPE_REGULAR ||
      g_file_info_get_size(info) > static_cast<goffset>(kMaximumEntryBytes)) {
    return true; // Foreign, oversized and symlink entries are never replaced.
  }
  const char *etag = g_file_info_get_etag(info);
  if (etag != nullptr)
    entry->etag = etag;
  g_autoptr(GFileInputStream) stream = g_file_read(file, nullptr, error);
  if (stream == nullptr)
    return false;
  std::vector<char> contents(kMaximumEntryBytes + 1);
  gsize read = 0;
  if (!g_input_stream_read_all(G_INPUT_STREAM(stream), contents.data(),
                               contents.size(), &read, nullptr, error) ||
      !g_input_stream_close(G_INPUT_STREAM(stream), nullptr, error)) {
    return false;
  }
  if (read > kMaximumEntryBytes ||
      !g_utf8_validate(contents.data(), read, nullptr) ||
      std::memchr(contents.data(), 0, read) != nullptr) {
    return true;
  }
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  if (!g_key_file_load_from_data(key_file, contents.data(), read,
                                 G_KEY_FILE_NONE, nullptr)) {
    return true;
  }
  entry->owned =
      SameString(key_file, kOwnerKey, executable_) &&
      SameString(key_file, G_KEY_FILE_DESKTOP_KEY_EXEC, Command()) &&
      SameString(key_file, G_KEY_FILE_DESKTOP_KEY_TYPE,
                 G_KEY_FILE_DESKTOP_TYPE_APPLICATION) &&
      g_key_file_get_integer(key_file, kGroup, kVersionKey, nullptr) == 1;
  const bool hidden = g_key_file_get_boolean(
      key_file, kGroup, G_KEY_FILE_DESKTOP_KEY_HIDDEN, nullptr);
  const bool gnome_disabled =
      g_key_file_has_key(key_file, kGroup, "X-GNOME-Autostart-enabled",
                         nullptr) &&
      !g_key_file_get_boolean(key_file, kGroup, "X-GNOME-Autostart-enabled",
                              nullptr);
  entry->enabled = entry->owned && !hidden && !gnome_disabled;
  return true;
}

bool DesktopAutostart::Read(bool *enabled, GError **error) const {
  Entry entry;
  if (!Inspect(&entry, error))
    return false;
  *enabled = entry.enabled;
  return true;
}

bool DesktopAutostart::Write(bool enabled, GError **error) const {
  Entry entry;
  if (!Inspect(&entry, error))
    return false;
  if (!enabled) {
    if (!entry.owned)
      return true;
    if (g_unlink(path_.c_str()) != 0)
      return FileError(error, "Remove autostart");
  } else {
    if (entry.exists && !entry.owned) {
      g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_EXISTS,
                          "Autostart entry belongs to another installation");
      return false;
    }
    const std::string contents = Contents();
    if (g_mkdir_with_parents(directory_.c_str(), 0700) != 0) {
      return FileError(error, "Create autostart directory");
    }
    g_autoptr(GFile) file = g_file_new_for_path(path_.c_str());
    if (entry.exists) {
      if (entry.etag.empty()) {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                            "Cannot safely replace autostart without an etag");
        return false;
      }
      if (!g_file_replace_contents(
              file, contents.data(), contents.size(), entry.etag.c_str(), FALSE,
              static_cast<GFileCreateFlags>(G_FILE_CREATE_PRIVATE |
                                            G_FILE_CREATE_REPLACE_DESTINATION),
              nullptr, nullptr, error)) {
        return false;
      }
    } else {
      // Publish a complete private inode without overwriting a concurrently
      // created entry. A failed write never leaves a partial startup command.
      std::string temporary = directory_ + "/.rainlink-autostart.XXXXXX";
      int fd = g_mkstemp_full(&temporary[0], O_RDWR | O_CLOEXEC, 0600);
      if (fd < 0)
        return FileError(error, "Create temporary autostart");
      gsize written = 0;
      while (written < contents.size()) {
        const ssize_t count =
            write(fd, contents.data() + written, contents.size() - written);
        if (count < 0 && errno == EINTR)
          continue;
        if (count <= 0)
          break;
        written += count;
      }
      bool complete = written == contents.size() && fsync(fd) == 0;
      if (!complete)
        FileError(error, "Write temporary autostart");
      if (close(fd) != 0 && complete) {
        complete = FileError(error, "Close temporary autostart");
      }
      if (complete && link(temporary.c_str(), path_.c_str()) != 0) {
        complete = FileError(error, "Publish autostart");
      }
      if (g_unlink(temporary.c_str()) != 0 && complete) {
        complete = FileError(error, "Remove temporary autostart");
      }
      if (!complete)
        return false;
    }
  }
  bool observed = false;
  if (!Read(&observed, error))
    return false;
  if (observed != enabled) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                        "Autostart did not pass readback");
    return false;
  }
  return true;
}
