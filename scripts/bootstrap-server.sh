#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MYAPP_HOME="${MYAPP_HOME:-$HOME/myapp}"
NETWORK_NAME="myapp-network"
UPSTREAM_FILE="$PROJECT_DIR/nginx/conf.d/board-upstream.conf"
UPSTREAM_TEMPLATE="$PROJECT_DIR/nginx/templates/board-upstream.conf"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

require_command docker

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or the current user cannot access it." >&2
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 is not available." >&2
    exit 1
fi

mkdir -p \
    "$PROJECT_DIR/nginx/conf.d" \
    "$MYAPP_HOME/infra/nginx/conf.d" \
    "$MYAPP_HOME/board"

if [ -f "$UPSTREAM_FILE" ]; then
    echo "Board upstream state already exists. Keeping the current state."
else
    cp "$UPSTREAM_TEMPLATE" "$UPSTREAM_FILE"
    echo "Board upstream state initialized with Blue."
fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Docker network already exists: $NETWORK_NAME"
else
    docker network create "$NETWORK_NAME" >/dev/null
    echo "Docker network created: $NETWORK_NAME"
fi

echo
echo "Server directories:"
echo "  $MYAPP_HOME/infra"
echo "  $MYAPP_HOME/board"

echo
echo "Running containers that publish port 80:"
PORT_80_CONTAINERS="$({
    docker ps --format '{{.Names}}\t{{.Ports}}' \
        | grep -E '(^|[,:])80->|0\.0\.0\.0:80->|\[::\]:80->' || true
})"

if [ -n "$PORT_80_CONTAINERS" ]; then
    printf '%s\n' "$PORT_80_CONTAINERS"
else
    echo "  none"
fi

echo
echo "Bootstrap check complete. No existing containers were stopped or removed."
