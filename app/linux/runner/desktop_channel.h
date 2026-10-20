#ifndef RAINLINK_DESKTOP_CHANNEL_H_
#define RAINLINK_DESKTOP_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The window owns this channel; it is detached before its Flutter view dies.
void rainlink_register_desktop_channel(GtkWindow *window,
                                       FlBinaryMessenger *messenger);

#endif // RAINLINK_DESKTOP_CHANNEL_H_
