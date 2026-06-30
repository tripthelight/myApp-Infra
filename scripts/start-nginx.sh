#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK_NAME="myapp-network"
NGINX_CONTAINER="myapp-nginx"

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

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Docker network does not exist: $NETWORK_NAME" >&2
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

detect_active_color() {
    service_name="$1"
    upstream_file="$PROJECT_DIR/nginx/conf.d/$service_name-upstream.conf"
    container_prefix="myapp-$service_name"

    if grep -Fq "$container_prefix-blue-1:8080" "$upstream_file" && \
       grep -Fq "$container_prefix-blue-2:8080" "$upstream_file"; then
        echo blue
    elif grep -Fq "$container_prefix-green-1:8080" "$upstream_file" && \
         grep -Fq "$container_prefix-green-2:8080" "$upstream_file"; then
        echo green
    else
        echo "Could not determine the active $service_name color." >&2
        exit 1
    fi
}

for service_name in board member; do
    active_color="$(detect_active_color "$service_name")"

    for instance in 1 2; do
        container="myapp-$service_name-$active_color-$instance"

        if [ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" != true ]; then
            echo "Required active container is not running: $container" >&2
            exit 1
        fi
    done
done

cd "$PROJECT_DIR"

echo "[1/4] Validate Docker Compose configuration"
docker compose config >/dev/null

echo "[2/4] Start Nginx"
docker compose up -d

echo "[3/4] Validate loaded Nginx configuration"
docker exec "$NGINX_CONTAINER" nginx -t

echo "[4/4] Request /board/hc and /member/hc"
for attempt in $(seq 1 30); do
    if docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O /dev/null http://127.0.0.1/board/hc && \
       docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O /dev/null http://127.0.0.1/member/hc; then
        break
    fi

    if [ "$attempt" -eq 30 ]; then
        docker logs "$NGINX_CONTAINER" || true
        echo "Nginx proxy health check failed." >&2
        exit 1
    fi

    echo "Waiting for Nginx: $attempt/30"
    sleep 2
done

for service_name in board member; do
    printf '%s: ' "$service_name"
    docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O - "http://127.0.0.1/$service_name/hc"
    echo
done

echo
docker ps --filter "name=$NGINX_CONTAINER" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "Nginx startup and service health check complete."
