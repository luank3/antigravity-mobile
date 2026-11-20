#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ADB:-$(command -v adb || echo "$HOME/.local/bin/adb")}"
SERIAL="${ANDROID_SERIAL:-10.0.2.81:5555}"
CONFIG_DIR="${AGYD_EMU_CONFIG:-$HOME/.config/agyd-emu}"
WORKSPACE="${AGYD_WORKSPACE:-$ROOT_DIR}"
AGY_BIN="${AGY_BIN:-$(command -v agy || echo "$HOME/.local/bin/agy")}"

RELAY_BIN="$ROOT_DIR/server/bin/agy-relay"
AGYD_BIN="$ROOT_DIR/server/bin/agyd"

if [ ! -x "$RELAY_BIN" ] || [ ! -x "$AGYD_BIN" ]; then
  echo "Building agy-relay and agyd binaries..."
  (cd "$ROOT_DIR/server" && go build -o bin/agy-relay ./cmd/agy-relay && go build -o bin/agyd ./cmd/agyd)
fi

mkdir -p "$CONFIG_DIR"

RELAY_PID=""
AGYD_PID=""

cleanup() {
  echo ""
  echo "Stopping emulator relay & agyd stack..."
  if [ -n "$AGYD_PID" ] && kill -0 "$AGYD_PID" 2>/dev/null; then
    kill "$AGYD_PID" 2>/dev/null || true
    wait "$AGYD_PID" 2>/dev/null || true
  fi
  if [ -n "$RELAY_PID" ] && kill -0 "$RELAY_PID" 2>/dev/null; then
    kill "$RELAY_PID" 2>/dev/null || true
    wait "$RELAY_PID" 2>/dev/null || true
  fi
  "$ADB" -s "$SERIAL" reverse --remove tcp:4001 >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

: > "$CONFIG_DIR/relay.log"
: > "$CONFIG_DIR/agyd.log"

echo "Starting agy-relay on 127.0.0.1:4001..."
"$RELAY_BIN" \
  --identity "$CONFIG_DIR/relay.key" \
  --listen /ip4/127.0.0.1/tcp/4001 \
  >"$CONFIG_DIR/relay.log" 2>&1 &
RELAY_PID=$!

RELAY_PEER_ID=""
for _ in $(seq 1 40); do
  if ! kill -0 "$RELAY_PID" 2>/dev/null; then
    echo "agy-relay exited unexpectedly:"
    cat "$CONFIG_DIR/relay.log"
    exit 1
  fi
  RELAY_PEER_ID="$(sed -n 's/.*agy-relay running (PeerID: \([^)]*\)).*/\1/p' "$CONFIG_DIR/relay.log" | head -n1 || true)"
  if [ -n "$RELAY_PEER_ID" ]; then
    break
  fi
  sleep 0.25
done

if [ -z "$RELAY_PEER_ID" ]; then
  echo "Timed out waiting for agy-relay PeerID:"
  cat "$CONFIG_DIR/relay.log"
  exit 1
fi
echo "agy-relay PeerID: $RELAY_PEER_ID"

echo "Setting up adb reverse tcp:4001 -> tcp:4001 on $SERIAL..."
"$ADB" -s "$SERIAL" reverse tcp:4001 tcp:4001

RELAY_ADDR="/ip4/127.0.0.1/tcp/4001/p2p/$RELAY_PEER_ID"
echo "Starting agyd host daemon (workspace: $WORKSPACE)..."
"$AGYD_BIN" run \
  --config-dir "$CONFIG_DIR" \
  --agy "$AGY_BIN" \
  --mdns=false \
  --force-private \
  --relay "$RELAY_ADDR" \
  --workspace "$WORKSPACE" \
  >"$CONFIG_DIR/agyd.log" 2>&1 &
AGYD_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$AGYD_PID" 2>/dev/null; then
    echo "agyd exited unexpectedly:"
    cat "$CONFIG_DIR/agyd.log"
    exit 1
  fi
  if [ -S "$CONFIG_DIR/control.sock" ]; then
    break
  fi
  sleep 0.25
done

if [ ! -S "$CONFIG_DIR/control.sock" ]; then
  echo "Timed out waiting for $CONFIG_DIR/control.sock:"
  cat "$CONFIG_DIR/agyd.log"
  exit 1
fi

sleep 1.5
echo ""
echo "=== agyd status ==="
"$AGYD_BIN" status --config-dir "$CONFIG_DIR"
echo ""
echo "=== agyd pair (scan QR or paste URI into Antigravity Mobile -> Hosts -> Pair) ==="
"$AGYD_BIN" pair --config-dir "$CONFIG_DIR"
echo ""
echo "Stack running (logs: $CONFIG_DIR/{relay,agyd}.log). Press Ctrl+C to stop."

wait "$AGYD_PID"
