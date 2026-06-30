#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONTAINER="myapp-nginx"
SERVICE_NAME="${1:-}"
TARGET="${2:-}"

if [[ ! "$SERVICE_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Usage: $0 service-name blue|green" >&2
    exit 1
fi

if [ "$TARGET" != blue ] && [ "$TARGET" != green ]; then
    echo "Usage: $0 service-name blue|green" >&2
    exit 1
fi

POOL_NAME="${SERVICE_NAME//-/_}_pool"
UPSTREAM_FILE="$PROJECT_DIR/nginx/conf.d/$SERVICE_NAME-upstream.conf"
BACKUP_FILE="$UPSTREAM_FILE.backup"
CONTAINER_PREFIX="myapp-$SERVICE_NAME"
HEALTH_URL="http://127.0.0.1/$SERVICE_NAME/hc"

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or the current user cannot access it." >&2
    exit 1
fi

if [ "$(docker inspect --format '{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null || true)" != true ]; then
    echo "Nginx container is not running: $NGINX_CONTAINER" >&2
    exit 1
fi

if [ ! -f "$UPSTREAM_FILE" ]; then
    echo "Upstream state does not exist: $UPSTREAM_FILE" >&2
    echo "Run the bootstrap script first." >&2
    exit 1
fi

if grep -Fq "$CONTAINER_PREFIX-$TARGET-1:8080" "$UPSTREAM_FILE"; then
    echo "$SERVICE_NAME upstream already uses $TARGET."
    exit 0
fi

echo "[1/5] Check both $SERVICE_NAME $TARGET containers directly"
for instance in 1 2; do
    container="$CONTAINER_PREFIX-$TARGET-$instance"

    if ! docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O /dev/null "http://$container:8080/hc"; then
        echo "Target container is not ready: $container" >&2
        exit 1
    fi
done

echo "[2/5] Write $SERVICE_NAME upstream: $TARGET"
cp "$UPSTREAM_FILE" "$BACKUP_FILE"

cat > "$UPSTREAM_FILE.next" <<EOF
upstream $POOL_NAME {
    least_conn;
    server $CONTAINER_PREFIX-$TARGET-1:8080 max_fails=3 fail_timeout=10s;
    server $CONTAINER_PREFIX-$TARGET-2:8080 max_fails=3 fail_timeout=10s;
    keepalive 32;
}
EOF

mv "$UPSTREAM_FILE.next" "$UPSTREAM_FILE"

rollback() {
    echo "Rolling $SERVICE_NAME upstream back to the previous configuration." >&2
    cp "$BACKUP_FILE" "$UPSTREAM_FILE"
    docker exec "$NGINX_CONTAINER" nginx -t
    docker exec "$NGINX_CONTAINER" nginx -s reload
}

echo "[3/5] Validate Nginx configuration"
if ! docker exec "$NGINX_CONTAINER" nginx -t; then
    rollback
    exit 1
fi

echo "[4/5] Reload Nginx"
docker exec "$NGINX_CONTAINER" nginx -s reload

echo "[5/5] Verify the proxied environment"
response=""
switched=false

for attempt in $(seq 1 10); do
    response="$(docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O - "$HEALTH_URL" || true)"

    if grep -Fq "\"env\":\"$TARGET\"" <<< "$response"; then
        switched=true
        break
    fi

    echo "Waiting for the $SERVICE_NAME $TARGET upstream: $attempt/10"
    sleep 1
done

if [ "$switched" != true ]; then
    echo "Unexpected proxy response: $response" >&2
    rollback
    exit 1
fi

rm -f "$BACKUP_FILE"

echo "Proxy response: $response"
echo "$SERVICE_NAME upstream switch complete: $TARGET"
