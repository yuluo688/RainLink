#!/usr/bin/env bash
# Runs core/session tests on a private D-Bus and a disposable keyring.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qa="$repo_root/build/qa/linux"
mkdir -p "$qa"
include_kde=false
if [[ "${1:-}" == --kde || "${2:-}" == --kde ]]; then include_kde=true; fi

if [[ "${1:-}" == "--inside" ]]; then
  [[ -n "${RAINLINK_QA_HOME:-}" && "$HOME" == "$RAINLINK_QA_HOME" && -d "$HOME" ]] || exit 2
  export XDG_STATE_HOME="$HOME/state"
  export XDG_CONFIG_HOME="$HOME/config"
  export XDG_CACHE_HOME="$HOME/cache"
  export XDG_DATA_HOME="$HOME/data"
  export XDG_RUNTIME_DIR="$HOME/runtime"
  export RAINLINK_TEST_SECRET_SERVICE=isolated
  export RAINLINK_TEST_GNOME_PROXY=isolated
  export XDG_CURRENT_DESKTOP=GNOME
  export GSETTINGS_BACKEND=dconf
  export RAINLINK_TEST_CORE_PATH="$qa/sing-box"
  export RAINLINK_TEST_HOST_PATH="$qa/rainlink-host"
  if [[ "$include_kde" == true ]]; then
    export RAINLINK_TEST_KDE_PROXY=isolated
    export RAINLINK_TEST_KDE_HELPER_PATH="$qa/rainlink-kde-proxy"
    export RAINLINK_TEST_PROXY_RESOLVER="$qa/rainlink-proxy-resolver"
  fi
  unset GNOME_KEYRING_CONTROL GNOME_KEYRING_PID
  mkdir -m 700 -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/keyring"
  # This password belongs only to the temporary test keyring and goes over stdin.
  head -c 32 /dev/urandom | base64 | /usr/bin/gnome-keyring-daemon --foreground --components=secrets --control-directory="$XDG_RUNTIME_DIR/keyring" --unlock > "$qa/keyring.log" 2>&1 &
  keyring_pid=$!
  stop_keyring() {
    kill "$keyring_pid" 2>/dev/null || true
    wait "$keyring_pid" 2>/dev/null || true
  }
  trap stop_keyring EXIT
  ready=false
  for ((i=0; i<50; i++)); do
    if dbus-send --session --dest=org.freedesktop.DBus --print-reply /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.freedesktop.secrets | grep -q 'boolean true'; then
      ready=true
      break
    fi
    sleep 0.1
  done
  [[ "$ready" == true ]] || { echo "Isolated Secret Service did not become ready" >&2; exit 1; }
  XDG_CURRENT_DESKTOP=RainLink-Unsupported "$qa/rainlink-host" status > "$qa/host-status-local.json"
  "$qa/rainlink-host" status > "$qa/host-status-gnome.json"
  if [[ "$include_kde" == true ]]; then
    XDG_CURRENT_DESKTOP=KDE "$qa/rainlink-host" status > "$qa/host-status-kde.json"
  fi
  cd "$repo_root/native/host"
  go vet ./...
  # Packages share one disposable keyring and the user-wide proxy lease.
  go test -p 1 -json -count=1 -timeout=240s ./... > "$qa/go-tests.jsonl"
  gdbus call --session --dest org.freedesktop.secrets --object-path /org/freedesktop/secrets --method org.freedesktop.Secret.Service.Lock "['/org/freedesktop/secrets/aliases/default']" > "$qa/keyring-lock.txt"
  RAINLINK_TEST_SECRET_SERVICE_LOCKED=isolated go test -json -count=1 -timeout=15s ./internal/securestore -run '^TestLinuxLockedSecretService$' > "$qa/locked-keyring-tests.jsonl"
  echo "Linux core, credentials and isolated desktop proxy tests passed (KDE enabled: $include_kde). TUN and desktop UI require separate verification."
  exit 0
fi

[[ "$(uname -s)" == Linux ]] || { echo "Run on Linux; this script does not use the current desktop keyring." >&2; exit 2; }
for tool in go python3 dbus-run-session dbus-send gdbus /usr/bin/gnome-keyring-daemon /usr/bin/secret-tool /usr/bin/gsettings /usr/bin/dconf; do
  command -v "$tool" >/dev/null || { echo "Required tool unavailable: $tool" >&2; exit 2; }
done
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported architecture" >&2; exit 2 ;;
esac
export GOTOOLCHAIN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["goVersion"])' "$repo_root/tools/core.lock.json")"
python3 "$repo_root/tools/setup_core.py" --platform "linux-$arch"
cp "$repo_root/build/host/linux-$arch/sing-box" "$qa/sing-box"
if [[ "$include_kde" == true ]]; then
  command -v /usr/bin/kreadconfig6 >/dev/null || { echo "KDE acceptance requires kreadconfig6." >&2; exit 2; }
  bash "$repo_root/tools/build_kde_proxy.sh" "$qa"
  cc -std=c11 -O2 -Wall -Wextra -Werror "$repo_root/tools/fixtures/linux_proxy_resolver.c" -o "$qa/rainlink-proxy-resolver" -l:libproxy.so.1
fi
(cd "$repo_root/native/host" && gofmt -l cmd internal > "$qa/gofmt.txt" && [[ ! -s "$qa/gofmt.txt" ]] && go build -trimpath -o "$qa/rainlink-host" ./cmd/rainlink-host)
# Reuse tool caches while moving HOME away from the user's keyring and settings.
export GOCACHE="$(go env GOCACHE)"
export GOMODCACHE="$(go env GOMODCACHE)"
export RAINLINK_QA_HOME="$(mktemp -d /tmp/rainlink-native-qa.XXXXXXXX)"
mkdir -m 700 -p "$RAINLINK_QA_HOME/state" "$RAINLINK_QA_HOME/config" "$RAINLINK_QA_HOME/cache" "$RAINLINK_QA_HOME/data" "$RAINLINK_QA_HOME/runtime" "$RAINLINK_QA_HOME/defaults"
cleanup_home() {
  case "$RAINLINK_QA_HOME" in
    /tmp/rainlink-native-qa.*) [[ ! -L "$RAINLINK_QA_HOME" ]] && rm -rf -- "$RAINLINK_QA_HOME" ;;
  esac
}
trap cleanup_home EXIT
# Activated dconf/Secret Service processes inherit the bus daemon's environment.
# Set the same directories before starting that daemon, not only inside it.
inside_flags=(--inside)
if [[ "$include_kde" == true ]]; then inside_flags+=(--kde); fi
unset GNOME_KEYRING_CONTROL GNOME_KEYRING_PID
HOME="$RAINLINK_QA_HOME" XDG_STATE_HOME="$RAINLINK_QA_HOME/state" XDG_CONFIG_HOME="$RAINLINK_QA_HOME/config" XDG_CONFIG_DIRS="$RAINLINK_QA_HOME/defaults" XDG_DATA_HOME="$RAINLINK_QA_HOME/data" XDG_CACHE_HOME="$RAINLINK_QA_HOME/cache" XDG_RUNTIME_DIR="$RAINLINK_QA_HOME/runtime" dbus-run-session -- bash "$0" "${inside_flags[@]}"
