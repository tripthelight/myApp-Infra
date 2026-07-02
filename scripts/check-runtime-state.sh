#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONTAINER="myapp-nginx"
NETWORK_NAME="myapp-network"
DEFAULT_CONF="$PROJECT_DIR/nginx/conf.d/default.conf"

detect_active_color() {
    service_name="$1"
    service_port="$2"

    if grep -Fq "server myapp-$service_name-blue-1:$service_port" "$DEFAULT_CONF" && \
       grep -Fq "server myapp-$service_name-blue-2:$service_port" "$DEFAULT_CONF"; then
        echo blue
    elif grep -Fq "server myapp-$service_name-green-1:$service_port" "$DEFAULT_CONF" && \
         grep -Fq "server myapp-$service_name-green-2:$service_port" "$DEFAULT_CONF"; then
        echo green
    else
        echo "Could not determine active $service_name color from $DEFAULT_CONF." >&2
        return 1
    fi
}

check_service() {
    service_name="$1"
    service_port="$2"
    direct_path="$3"
    proxy_path="$4"
    active_color="$(detect_active_color "$service_name" "$service_port")"

    echo
    echo "[$service_name] active color: $active_color"

    for instance in 1 2; do
        container="myapp-$service_name-$active_color-$instance"

        if [ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" != true ]; then
            echo "Active container is not running: $container" >&2
            return 1
        fi

        docker exec "$NGINX_CONTAINER" \
            wget -q -T 2 -O /dev/null "http://$container:$service_port$direct_path"

        echo "Direct health check OK: $container"
    done

    response="$(docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O - "http://127.0.0.1$proxy_path" || true)"

    if [ "$service_name" = front ]; then
        [ -n "$response" ] || {
            echo "Unexpected empty Front proxy response." >&2
            return 1
        }
    elif ! grep -Fq "\"env\":\"$active_color\"" <<< "$response"; then
        echo "Unexpected $service_name proxy response: $response" >&2
        return 1
    fi

    echo "Proxy health check OK: $proxy_path"
}

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or current user cannot access it." >&2
    exit 1
fi

docker network inspect "$NETWORK_NAME" >/dev/null

if [ "$(docker inspect --format '{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null || true)" != true ]; then
    echo "Nginx container is not running: $NGINX_CONTAINER" >&2
    exit 1
fi

[ -f "$DEFAULT_CONF" ] || {
    echo "Nginx default config does not exist: $DEFAULT_CONF" >&2
    exit 1
}

echo "[1/5] Validate loaded Nginx configuration"
docker exec "$NGINX_CONTAINER" nginx -t

echo "[2/5] Check Front runtime state"
check_service front 80 / /

echo
echo "[3/5] Check Member runtime state"
check_service member 8080 /hc /member/hc

echo
echo "[4/5] Check Board runtime state"
check_service board 8080 /hc /board/hc

echo
echo "[5/5] Running myApp containers"
docker ps \
    --filter 'name=myapp-' \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "Runtime state check complete."