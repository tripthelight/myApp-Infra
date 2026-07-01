#!/usr/bin/env bash

set -Eeuo pipefail

NGINX_CONTAINER="myapp-nginx"
NGINX_CONF="${NGINX_CONF:-/home/um/myApp-Nginx/conf.d/default.conf}"

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or the current user cannot access it." >&2
    exit 1
fi

if [ "$(docker inspect --format '{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null || true)" != true ]; then
    echo "Nginx container is not running: $NGINX_CONTAINER" >&2
    exit 1
fi

if [ ! -f "$NGINX_CONF" ]; then
    echo "Nginx config does not exist: $NGINX_CONF" >&2
    exit 1
fi

for service_name in front member board; do
    if ! grep -Eq "^upstream ${service_name}[[:space:]]*\\{" "$NGINX_CONF"; then
        echo "Nginx upstream does not exist: $service_name" >&2
        exit 1
    fi
done

echo "[1/3] Validate Nginx configuration"
docker exec "$NGINX_CONTAINER" nginx -t

echo "[2/3] Reload Nginx"
docker exec "$NGINX_CONTAINER" nginx -s reload

echo "[3/3] Check Front, Member, and Board routes"

for request in 1 2; do
    printf 'front request %s: ' "$request"
    docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O /dev/null "http://127.0.0.1/"
    echo "OK"
done

for service_name in member board; do
    for request in 1 2; do
        printf '%s request %s: ' "$service_name" "$request"
        docker exec "$NGINX_CONTAINER" \
            wget -q -T 2 -O - "http://127.0.0.1/$service_name/hc"
        echo
    done
done

echo
echo "Nginx reload and route checks complete."
