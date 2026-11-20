#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VPS_HOST="${1:-${VPS_HOST:-}}"
if [ -z "$VPS_HOST" ]; then
  echo "Usage: VPS_HOST=<ip-or-domain> [VPS_USER=root] [SSH_PORT=22] [PUBLIC_HOST=<dns-or-ip>] [ALLOW_PEERS=peer1,peer2] $0"
  exit 1
fi

VPS_USER="${VPS_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_DIR="${REMOTE_DIR:-/opt/antigravity-relay}"
PUBLIC_HOST="${PUBLIC_HOST:-$VPS_HOST}"
ALLOW_PEERS="${ALLOW_PEERS:-}"
SSH_TARGET="${VPS_USER}@${VPS_HOST}"
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)

echo "Deploying agy-relay bundle to ${SSH_TARGET}:${REMOTE_DIR}..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_DIR/server' '$REMOTE_DIR/deploy/relay'"

tar -C "$ROOT_DIR" \
  --exclude='server/bin' \
  --exclude='*.log' \
  -czf - server deploy/relay \
  | ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "tar -C '$REMOTE_DIR' -xzf -"

if [ -n "$ALLOW_PEERS" ]; then
  ALLOW_LINES="$(echo "$ALLOW_PEERS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s -- "$REMOTE_DIR" "$PUBLIC_HOST" "$ALLOW_LINES" <<'EOF'
set -euo pipefail
REMOTE_DIR="$1"
PUBLIC_HOST="$2"
ALLOW_LINES="$3"

cat > "$REMOTE_DIR/deploy/relay/docker-compose.override.yml" <<YAML
services:
  agy-relay:
    command:
      - "--public-host"
      - "${PUBLIC_HOST}"
      - "--allow-file"
      - "/data/allowed_peers.txt"
YAML

cd "$REMOTE_DIR/deploy/relay"
printf '%s\n' "$ALLOW_LINES" | docker compose run --rm -T --no-deps --entrypoint sh agy-relay \
  -c 'mkdir -p /data && cat > /data/allowed_peers.txt && chmod 600 /data/allowed_peers.txt'
EOF
else
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -f '$REMOTE_DIR/deploy/relay/docker-compose.override.yml'"
fi

echo "Building and starting agy-relay container (open ports 4001/tcp & 4001/udp)..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "cd '$REMOTE_DIR/deploy/relay' && AGY_RELAY_HOST='$PUBLIC_HOST' docker compose up -d --build && sleep 2 && docker compose logs --tail=30 agy-relay"

echo ""
echo "Deployment complete."
echo "Hot-reload PeerID ACL later without restarting:"
echo "  ssh -p $SSH_PORT $SSH_TARGET 'docker kill -s HUP agy-relay'"
