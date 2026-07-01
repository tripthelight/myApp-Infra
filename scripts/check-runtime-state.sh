#!/usr/bin/env bash

set -Eeuo pipefail

NGINX_CONTAINER="myapp-nginx"
NETWORK_NAME="myapp-network"
NGINX_CONF="${NGINX_CONF:-/home/um/myApp-Infra/nginx/conf.d/default.conf}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

service_port() {
    case "$1" in
        front) echo 80 ;;
        member|board) echo 8080 ;;
        *)
            echo "Unknown service: $1" >&2
            return 1
            ;;
    esac
}

detect_active_color() {
    service_name="$1"
    port="$(service_port "$service_name")"
    container_prefix="myapp-$service_name"

    if [ ! -f "$NGINX_CONF" ]; then
        echo "Nginx config does not exist: $NGINX_CONF" >&2
        return 1
    fi

    if grep -Fq "$container_prefix-blue-1:$port" "$NGINX_CONF" && \
       grep -Fq "$container_prefix-blue-2:$port" "$NGINX_CONF"; then
        echo blue
    elif grep -Fq "$container_prefix-green-1:$port" "$NGINX_CONF" && \
         grep -Fq "$container_prefix-green-2:$port" "$NGINX_CONF"; then
        echo green
    else
        echo "Could not determine the active $service_name color." >&2
        return 1
    fi
}

check_direct_service() {
    service_name="$1"
    active_color="$2"
    port="$(service_port "$service_name")"
    container_prefix="myapp-$service_name"

    for instance in 1 2; do
        container="$container_prefix-$active_color-$instance"

        if [ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" != true ]; then
            echo "Active container is not running: $container" >&2
            return 1
        fi

        if [ "$service_name" = front ]; then
            docker exec "$NGINX_CONTAINER" \
                wget -q -T 2 -O /dev/null "http://$container:$port/"
        else
            docker exec "$NGINX_CONTAINER" \
                wget -q -T 2 -O /dev/null "http://$container:$port/hc"
        fi

        echo "Direct health check OK: $container"
    done
}

check_proxy_service() {
    service_name="$1"
    active_color="$2"

    if [ "$service_name" = front ]; then
        docker exec "$NGINX_CONTAINER" \
            wget -q -T 2 -O /dev/null "http://127.0.0.1/"
        echo "Proxy health check OK: / -> front $active_color"
        return 0
    fi

    response="$(docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O - "http://127.0.0.1/$service_name/hc" || true)"

    if ! grep -Fq "\"env\":\"$active_color\"" <<< "$response"; then
        echo "Unexpected $service_name proxy response: $response" >&2
        return 1
    fi

    echo "Proxy health check OK: /$service_name/hc -> $response"
}

check_service() {
    service_name="$1"
    active_color="$(detect_active_color "$service_name")"

    echo
    echo "[$service_name] active color: $active_color"

    check_direct_service "$service_name" "$active_color"
    check_proxy_service "$service_name" "$active_color"
}

require_command docker

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or the current user cannot access it." >&2
    exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Docker network does not exist: $NETWORK_NAME" >&2
    exit 1
fi

if [ "$(docker inspect --format '{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null || true)" != true ]; then
    echo "Nginx container is not running: $NGINX_CONTAINER" >&2
    exit 1
fi

echo "[1/5] Validate loaded Nginx configuration"
docker exec "$NGINX_CONTAINER" nginx -t

echo "[2/5] Check Front runtime state"
check_service front

echo
echo "[3/5] Check Member runtime state"
check_service member

echo
echo "[4/5] Check Board runtime state"
check_service board

echo
echo "[5/5] Running myApp containers"
docker ps \
    --filter 'name=myapp-nginx' \
    --filter 'name=myapp-front-' \
    --filter 'name=myapp-member-' \
    --filter 'name=myapp-board-' \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "Runtime state check complete."
