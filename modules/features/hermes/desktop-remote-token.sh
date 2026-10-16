# Prints the session token of the Hermes backend at $1 (default
# http://127.0.0.1:9119), read from the page it serves to loopback clients:
# here head's hermes-serve, reached through hermes-desktop-tunnel. Prints
# nothing, and says why on stderr, when there is none. Always exits 0.
# Packaged with writeShellApplication (desktop-client.nix), which adds the
# shebang and `set -o errexit -o nounset -o pipefail`.
backend="${1:-http://127.0.0.1:9119}"
for _ in 1 2 3; do
  tok="$(curl -fsS --max-time 3 "$backend/" 2>/dev/null \
    | sed -n 's/.*__HERMES_SESSION_TOKEN__[[:space:]]*=[[:space:]]*"\([^"\\]*\)".*/\1/p' \
    | head -n 1 || true)"
  if [ -n "$tok" ]; then
    printf '%s\n' "$tok"
    exit 0
  fi
  sleep 1
done
echo "hermes-desktop: no session token from $backend; is the tunnel up? (systemctl --user status hermes-desktop-tunnel)" >&2
