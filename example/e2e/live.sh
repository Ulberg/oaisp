#!/usr/bin/env bash
# Live round-trip: start the example Wisp/mist server, then call it with an
# openapi-fetch client and assert the responses. Run after run.sh (which
# installs the node tooling). Requires gleam + Erlang/OTP 27, Node.js, curl.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
example_dir="$(dirname "$here")"
log="$(mktemp)"

echo "==> Starting the example server"
(cd "$example_dir" && exec gleam run) >"$log" 2>&1 &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> Waiting for http://localhost:8080"
ready=
for _ in $(seq 1 90); do
  if curl -sf -o /dev/null "http://localhost:8080/todos/ping"; then
    ready=1
    break
  fi
  sleep 1
done
if [ -z "$ready" ]; then
  echo "server did not become ready; log follows:"
  cat "$log"
  exit 1
fi

echo "==> Calling the server with the openapi-fetch client"
cd "$here"
[ -d node_modules ] || npm install --no-audit --no-fund --silent
node live.mjs
