#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONTAINER="myapp-nginx"

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or the current user cannot access it." >&2
    exit 1
fi

if [ "$(docker inspect --format '{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null || true)" != true ]; then
    echo "Nginx container is not running: $NGINX_CONTAINER" >&2
    exit 1
fi

for service_name in board member; do
    upstream_file="$PROJECT_DIR/nginx/conf.d/$service_name-upstream.conf"

    if [ ! -f "$upstream_file" ]; then
        echo "Upstream state does not exist: $upstream_file" >&2
        echo "Run the bootstrap script first." >&2
        exit 1
    fi
done

echo "[1/3] Validate Nginx configuration"
docker exec "$NGINX_CONTAINER" nginx -t

echo "[2/3] Reload Nginx"
docker exec "$NGINX_CONTAINER" nginx -s reload

echo "[3/3] Check Board and Member routes"
for service_name in board member; do
    for request in 1 2; do
        printf '%s request %s: ' "$service_name" "$request"
        docker exec "$NGINX_CONTAINER" \
            wget -q -T 2 -O - "http://127.0.0.1/$service_name/hc"
        echo
    done
done

echo
echo "Nginx reload and route checks complete."
