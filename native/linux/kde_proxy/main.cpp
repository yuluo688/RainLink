// This unprivileged helper changes only eight keys in the current user's
// kioslaverc. Recovery is owned by the host's encrypted, user-wide lease.
#include <KConfig>
#include <KConfigGroup>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <cstdio>
#include <unistd.h>

namespace {
constexpr qint64 maxInput = 32 * 1024;
constexpr qint64 maxConfig = 1024 * 1024;
constexpr qsizetype maxValue = 2048;
const QString groupName = QStringLiteral("Proxy Settings");
const QString fileName = QStringLiteral("kioslaverc");
const QStringList keys = {QStringLiteral("ProxyType"), QStringLiteral("httpProxy"), QStringLiteral("httpsProxy"),
                          QStringLiteral("ftpProxy"), QStringLiteral("socksProxy"), QStringLiteral("Proxy Config Script"),
                          QStringLiteral("NoProxyFor"), QStringLiteral("ReversedException")};

int fail() {
    // Library diagnostics and supplied values must never reach host logs.
    std::fputs("KDE proxy configuration unavailable\n", stderr);
    return 1;
}

bool validValue(const QString &value) {
    return value.toUtf8().size() <= maxValue && !value.contains(QChar::Null) &&
           !value.contains(QLatin1Char('\n')) && !value.contains(QLatin1Char('\r'));
}

bool safeDirectory(QString path) {
    // Permit a missing config directory, but only below a private user-owned
    // ancestor. Do not follow symlinks or write through shared directories.
    while (!QFileInfo::exists(path)) {
        if (QFileInfo(path).isSymLink()) return false;
        const QString parent = QFileInfo(path).absolutePath();
        if (parent == path) return false;
        path = parent;
    }
    const QFileInfo info(path);
    return info.isDir() && !info.isSymLink() && info.canonicalFilePath() == QDir::cleanPath(path) && info.ownerId() == getuid() &&
           !(info.permissions() & (QFile::WriteGroup | QFile::WriteOther));
}

bool supportedFile(const QString &path) {
    const QFileInfo info(path);
    if (info.isSymLink()) return false;
    if (!info.exists()) return true;
    if (!info.isFile() || info.ownerId() != getuid() || info.size() > maxConfig ||
        (info.permissions() & (QFile::WriteGroup | QFile::WriteOther))) return false;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;
    const QByteArray bytes = file.read(maxConfig + 1);
    if (bytes.size() > maxConfig || bytes.contains('\0')) return false;
    bool proxyGroup = false;
    for (QByteArray line : bytes.split('\n')) {
        line = line.trimmed();
        if (line.startsWith('[')) {
            proxyGroup = line == "[Proxy Settings]";
            // KConfig handles immutable groups; reject unsupported group tags.
            if (line.startsWith("[Proxy Settings]") && line != "[Proxy Settings]" && line != "[Proxy Settings][$i]") return false;
            continue;
        }
        if (!proxyGroup || line.startsWith('#')) continue;
        const qsizetype equal = line.indexOf('=');
        const QByteArray name = (equal < 0 ? line : line.left(equal)).trimmed();
        for (const QString &key : keys) {
            // Localized, expansion and deletion flags require an exact raw
            // representation. Fail closed rather than normalizing them away.
            if (name.startsWith(key.toUtf8() + '[')) return false;
        }
    }
    return true;
}

QJsonObject snapshot(KConfig &local) {
    const KConfigGroup group = local.group(groupName);
    QJsonObject result;
    for (const QString &key : keys) {
        result.insert(QLatin1Char('/') + key,
                      group.hasKey(key) ? QStringLiteral("v:") + group.readEntryUntranslated(key) : QString());
    }
    return result;
}

bool validValues(const QJsonObject &values) {
    if (values.size() != keys.size()) return false;
    for (const QString &key : keys) {
        const QJsonValue item = values.value(QLatin1Char('/') + key);
        if (!item.isString()) return false;
        const QString value = item.toString();
        if (!validValue(value) || (!value.isEmpty() && !value.startsWith(QLatin1String("v:")))) return false;
    }
    return true;
}

bool writable(KConfig &effective) {
    if (effective.accessMode() != KConfig::ReadWrite || effective.isImmutable()) return false;
    const KConfigGroup group = effective.group(groupName);
    if (group.isImmutable()) return false;
    for (const QString &key : keys) {
        if (group.isEntryImmutable(key)) return false;
    }
    return true;
}
} // namespace

int main(int argc, char **argv) {
    qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &) {});
    QCoreApplication app(argc, argv);
    if (argc != 1 || getuid() != geteuid() || !QDBusConnection::sessionBus().isConnected()) return fail();
    QFile input;
    if (!input.open(stdin, QIODevice::ReadOnly, QFileDevice::DontCloseHandle)) return fail();
    QByteArray bytes = input.read(maxInput + 1);
    if (bytes.size() > maxInput) return fail();
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &error);
    bytes.fill('\0');
    if (error.error != QJsonParseError::NoError || !document.isObject()) return fail();
    const QJsonObject request = document.object();
    const QString operation = request.value(QStringLiteral("operation")).toString();
    const bool writing = operation == QLatin1String("write");
    if (request.value(QStringLiteral("version")).toInt() != 1 ||
        (!writing && operation != QLatin1String("snapshot")) || request.size() != (writing ? 4 : 3)) return fail();
    const QString root = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    if (!QDir::isAbsolutePath(root) || QDir::cleanPath(root) != request.value(QStringLiteral("configRoot")).toString() || !safeDirectory(root)) return fail();
    const QString path = QDir(root).filePath(fileName);
    if (!supportedFile(path)) return fail();
    // Relative names keep system defaults, lock-down and /kioslaverc D-Bus
    // notifications. SimpleConfig distinguishes a local override from defaults.
    KConfig effective(fileName, KConfig::NoGlobals);
    KConfig local(path, KConfig::SimpleConfig);
    const bool available = writable(effective);
    QJsonObject values = snapshot(local);
    if (!validValues(values)) return fail();
    if (writing) {
        if (!available || !request.value(QStringLiteral("values")).isObject()) return fail();
        const QJsonObject desired = request.value(QStringLiteral("values")).toObject();
        if (!validValues(desired)) return fail();
        KConfigGroup group = effective.group(groupName);
        for (const QString &key : keys) {
            const QString value = desired.value(QLatin1Char('/') + key).toString();
            if (value.isEmpty()) group.revertToDefault(key, KConfig::Persistent | KConfig::Notify);
            else group.writeEntry(key, value.mid(2), KConfig::Persistent | KConfig::Notify);
        }
        if (!effective.sync()) {
            // Suppress destructor retry after a reported failure; the durable
            // journal lets the host restore using a fresh configuration object.
            effective.markAsClean();
            return fail();
        }
        local.reparseConfiguration();
        values = snapshot(local);
        if (values != desired) return fail();
        QCoreApplication::processEvents();
    }
    QJsonObject response{{QStringLiteral("version"), 1}, {QStringLiteral("available"), available}, {QStringLiteral("values"), values}};
    QByteArray output = QJsonDocument(response).toJson(QJsonDocument::Compact);
    QFile stdoutFile;
    if (!stdoutFile.open(stdout, QIODevice::WriteOnly, QFileDevice::DontCloseHandle)) return fail();
    const bool success = stdoutFile.write(output) == output.size() && stdoutFile.flush();
    output.fill('\0');
    return success ? 0 : fail();
}
