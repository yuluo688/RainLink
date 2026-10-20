#include <execinfo.h>
#include <glib.h>
#include <unistd.h>

static void trace(GLogLevelFlags level) {
  if (level & (G_LOG_LEVEL_WARNING | G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_ERROR)) {
    void* frames[48];
    const int count = backtrace(frames, 48);
    const char message[] = "RAINLINK_QA_DIAGNOSTIC_STACK\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
  }
}

static void handler(const gchar* domain, GLogLevelFlags level,
                    const gchar* message, gpointer unused) {
  (void)unused;
  trace(level);
  g_log_default_handler(domain, level, message, NULL);
}

static GLogWriterOutput writer(GLogLevelFlags level, const GLogField* fields,
                               gsize count, gpointer unused) {
  (void)unused;
  trace(level);
  return g_log_writer_default(level, fields, count, NULL);
}

__attribute__((constructor)) static void install(void) {
  g_log_set_default_handler(handler, NULL);
  g_log_set_writer_func(writer, NULL, NULL);
}
