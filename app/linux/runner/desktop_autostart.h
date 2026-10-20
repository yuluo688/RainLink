#ifndef RAINLINK_DESKTOP_AUTOSTART_H_
#define RAINLINK_DESKTOP_AUTOSTART_H_

#include <gio/gio.h>

#include <string>

// Owns only this installation's current-user XDG autostart entry.
class DesktopAutostart {
public:
  DesktopAutostart(std::string config_directory, std::string executable);

  bool Read(bool *enabled, GError **error) const;
  bool Write(bool enabled, GError **error) const;

private:
  struct Entry;
  bool Inspect(Entry *entry, GError **error) const;
  std::string Command() const;
  std::string Contents() const;

  const std::string directory_;
  const std::string path_;
  const std::string executable_;
};

#endif // RAINLINK_DESKTOP_AUTOSTART_H_
