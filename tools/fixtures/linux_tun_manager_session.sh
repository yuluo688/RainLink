#!/bin/sh
# Ordinary-user client only, inside the disposable network/rootfs fixture.
set -eu
[ "$(id -u)" = 65534 ] || exit 2
[ "${RAINLINK_TEST_MANAGER_NAMESPACE:-}" = isolated ] || exit 2
[ "$#" = 1 ] || exit 2
test_binary=$1
export HOME="$RAINLINK_MANAGER_FIXTURE_HOME"
export XDG_STATE_HOME="$HOME/state" XDG_CONFIG_HOME="$HOME/config"
export XDG_DATA_HOME="$HOME/data" XDG_CACHE_HOME="$HOME/cache"
export XDG_RUNTIME_DIR="$HOME/runtime" XDG_CONFIG_DIRS="$HOME/defaults"
export RAINLINK_TEST_SECRET_SERVICE=isolated
mkdir -m 700 -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR/keyring" "$XDG_CONFIG_DIRS"
unset GNOME_KEYRING_CONTROL GNOME_KEYRING_PID DBUS_SESSION_BUS_ADDRESS
exec /usr/bin/dbus-run-session -- /bin/sh -c '
set -eu
head -c 32 /dev/urandom | base64 | /usr/bin/gnome-keyring-daemon --foreground --components=secrets --control-directory="$XDG_RUNTIME_DIR/keyring" --unlock > "$HOME/keyring.log" 2>&1 &
keyring_pid=$!
trap '\''kill "$keyring_pid" 2>/dev/null || true; wait "$keyring_pid" 2>/dev/null || true'\'' EXIT
ready=false
for i in $(seq 1 50); do
  if dbus-send --session --dest=org.freedesktop.DBus --print-reply /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.freedesktop.secrets | grep -q "boolean true"; then ready=true; break; fi
  sleep 0.1
done
[ "$ready" = true ] || exit 3
"$1" -test.run="${RAINLINK_MANAGER_TEST_PATTERN:-^TestLinuxTUNManagerClientFixture$}" -test.timeout=35s
' rainlink-manager-fixture "$test_binary"
