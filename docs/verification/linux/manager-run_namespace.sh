#!/bin/sh
set -eu
workspace=/mnt/host/c/Users/FalingFliff/Documents/ChatGPT/RainLink
qa="$workspace/build/qa/linux-manager"
parent_namespace=$(readlink /proc/self/ns/net)
save_parent_state() {
  ip -o link show > "$qa/parent-links-$1.txt"
  ip -4 route show table all > "$qa/parent-routes4-$1.txt"
  ip -6 route show table all > "$qa/parent-routes6-$1.txt"
  ip -4 rule show > "$qa/parent-rules4-$1.txt"
  ip -6 rule show > "$qa/parent-rules6-$1.txt"
}
# WSL starts IPv6 link-local DAD when this stopped distribution is launched.
# Keep the before/after comparison exact, but begin it after that startup phase.
sleep 2
save_parent_state before
fixture_result=0
unshare --mount --net --pid --fork --mount-proc --kill-child=SIGKILL -- /bin/sh "$qa/bootstrap.sh" "$parent_namespace" || fixture_result=$?
save_parent_state after
for kind in links routes4 routes6 rules4 rules6; do cmp "$qa/parent-$kind-before.txt" "$qa/parent-$kind-after.txt"; done
fixture_namespace=$(cat "$qa/fixture-netns.txt")
for process in /proc/[0-9]*; do
  [ "$(readlink "$process/ns/net" 2>/dev/null || true)" != "$fixture_namespace" ] || exit 3
done
printf 'Parent links/routes/rules unchanged. No fixture network namespace process remains.\n'
exit "$fixture_result"
