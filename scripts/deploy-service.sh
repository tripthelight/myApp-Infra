#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_NAME="${1:-}"
SERVICE_PORT="${2:-}"
DIRECT_HEALTH_PATH="${3:-}"
PROXY_HEALTH_PATH="${4:-}"

NGINX_CONTAINER="${NGINX_CONTAINER:-myapp-nginx}"
NETWORK_NAME="${NETWORK_NAME:-myapp-network}"
DEFAULT_CONF="$PROJECT_DIR/nginx/conf.d/default.conf"
IMAGE_OVERRIDE="${IMAGE_OVERRIDE:-}"
DRAIN_SECONDS="${DRAIN_SECONDS:-10}"
STABILIZATION_SECONDS="${STABILIZATION_SECONDS:-30}"
CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-2}"

usage() {
    echo "Usage: $0 front|member|board service-port direct-health-path proxy-health-path" >&2
    exit 1
}

[[ "$SERVICE_NAME" =~ ^(front|member|board)$ ]] || usage
[[ "$SERVICE_PORT" =~ ^[0-9]+$ ]] || usage
[ -n "$DIRECT_HEALTH_PATH" ] || usage
[ -n "$PROXY_HEALTH_PATH" ] || usage

if [ -z "$IMAGE_OVERRIDE" ]; then
    echo "IMAGE_OVERRIDE is required, for example myapp-member:abc123." >&2
    exit 1
fi

write_action_output() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
    fi
}

detect_active_color() {
    if grep -Fq "server myapp-$SERVICE_NAME-blue-1:$SERVICE_PORT" "$DEFAULT_CONF"; then
        echo blue
    elif grep -Fq "server myapp-$SERVICE_NAME-green-1:$SERVICE_PORT" "$DEFAULT_CONF"; then
        echo green
    else
        echo "Could not determine active $SERVICE_NAME color from $DEFAULT_CONF." >&2
        exit 1
    fi
}

opposite_color() {
    if [ "$1" = blue ]; then
        echo green
    else
        echo blue
    fi
}

wait_for_container() {
    container="$1"
    url="http://$container:$SERVICE_PORT$DIRECT_HEALTH_PATH"

    for attempt in $(seq 1 30); do
        echo "Health check $container: $attempt/30"

        if docker run --rm --network "$NETWORK_NAME" busybox:1.36 \
            wget -q -T 2 -O /dev/null "$url"; then
            return 0
        fi

        sleep 2
    done

    docker logs --tail 200 "$container" || true
    echo "Health check failed: $container" >&2
    return 1
}

write_default_conf_for_target() {
    target="$1"
    tmp_file="$DEFAULT_CONF.next"

    awk -v service="$SERVICE_NAME" \
        -v port="$SERVICE_PORT" \
        -v target="$target" '
        BEGIN { in_block = 0 }
        $0 ~ "^upstream " service " \\{" {
            print "upstream " service " {"
            print "    server myapp-" service "-" target "-1:" port ";"
            print "    server myapp-" service "-" target "-2:" port ";"
            print "}"
            in_block = 1
            next
        }
        in_block == 1 && $0 == "}" {
            in_block = 0
            next
        }
        in_block == 0 { print }
    ' "$DEFAULT_CONF" > "$tmp_file"

    if ! grep -Fq "server myapp-$SERVICE_NAME-$target-1:$SERVICE_PORT" "$tmp_file"; then
        rm -f "$tmp_file"
        echo "Failed to rewrite upstream $SERVICE_NAME in $DEFAULT_CONF." >&2
        exit 1
    fi

    mv "$tmp_file" "$DEFAULT_CONF"
}

verify_proxy() {
    target="$1"
    response="$(docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O - "http://127.0.0.1$PROXY_HEALTH_PATH" || true)"

    if [ "$SERVICE_NAME" = front ]; then
        [ -n "$response" ] || {
            echo "Unexpected empty Front proxy response." >&2
            return 1
        }
    elif ! grep -Fq "\"env\":\"$target\"" <<< "$response"; then
        echo "Unexpected $SERVICE_NAME proxy response: $response" >&2
        return 1
    fi

    echo "Proxy response OK: $PROXY_HEALTH_PATH"
}

cleanup_target() {
    color="$1"
    echo "Remove failed $SERVICE_NAME $color containers only."
    docker rm -f \
        "myapp-$SERVICE_NAME-$color-1" \
        "myapp-$SERVICE_NAME-$color-2" \
        2>/dev/null || true
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

CURRENT="$(detect_active_color)"
TARGET="$(opposite_color "$CURRENT")"
BACKUP_FILE="$DEFAULT_CONF.backup"

write_action_output previous_color "$CURRENT"
write_action_output target_color "$TARGET"

echo "$SERVICE_NAME deployment plan: $CURRENT -> $TARGET"
echo "Image: $IMAGE_OVERRIDE"

echo "[1/7] Start $SERVICE_NAME $TARGET containers"
cleanup_target "$TARGET"

DOCKER_ENV_ARGS=(
    -e APP_COLOR="$TARGET"
    -e SERVER_PORT="$SERVICE_PORT"
)

if [ "$SERVICE_NAME" = member ] || [ "$SERVICE_NAME" = board ]; then
    MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:-$PROJECT_DIR/secrets/mariadb_root.txt}"

    if [ ! -f "$MARIADB_ROOT_PASSWORD_FILE" ]; then
        echo "MariaDB root password file does not exist: $MARIADB_ROOT_PASSWORD_FILE" >&2
        exit 1
    fi

    MARIADB_ROOT_PASSWORD="$(tr -d '\r\n' < "$MARIADB_ROOT_PASSWORD_FILE")"

    DOCKER_ENV_ARGS+=(
        -e SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mariadb://myapp-mariadb:3306/myapp}"
        -e SPRING_DATASOURCE_USERNAME="${SPRING_DATASOURCE_USERNAME:-root}"
        -e SPRING_DATASOURCE_PASSWORD="$MARIADB_ROOT_PASSWORD"
    )
fi

for instance in 1 2; do
    docker run -d \
        --name "myapp-$SERVICE_NAME-$TARGET-$instance" \
        --network "$NETWORK_NAME" \
        --restart unless-stopped \
        "${DOCKER_ENV_ARGS[@]}" \
        -e SERVER_NAME="${SERVICE_NAME}_${TARGET}_${instance}" \
        -e DISPLAY_SERVER_ADDRESS="myapp-$SERVICE_NAME-$TARGET-$instance" \
        "$IMAGE_OVERRIDE"
done

echo "[2/7] Check $SERVICE_NAME $TARGET containers"
for instance in 1 2; do
    wait_for_container "myapp-$SERVICE_NAME-$TARGET-$instance" || {
        cleanup_target "$TARGET"
        write_action_output deployment_status FAILED
        exit 1
    }
done

echo "[3/7] Switch $SERVICE_NAME upstream in default.conf"
cp "$DEFAULT_CONF" "$BACKUP_FILE"
write_default_conf_for_target "$TARGET"

echo "[4/7] Validate Nginx config"
if ! docker exec "$NGINX_CONTAINER" nginx -t; then
    cp "$BACKUP_FILE" "$DEFAULT_CONF"
    docker exec "$NGINX_CONTAINER" nginx -t || true
    cleanup_target "$TARGET"
    write_action_output deployment_status FAILED
    exit 1
fi

echo "[5/7] Reload Nginx"
docker exec "$NGINX_CONTAINER" nginx -s reload

echo "[6/7] Stabilize $SERVICE_NAME $TARGET"
checks=$(((STABILIZATION_SECONDS + CHECK_INTERVAL_SECONDS - 1) / CHECK_INTERVAL_SECONDS))

for check in $(seq 1 "$checks"); do
    for instance in 1 2; do
        wait_for_container "myapp-$SERVICE_NAME-$TARGET-$instance" || {
            cp "$BACKUP_FILE" "$DEFAULT_CONF"
            docker exec "$NGINX_CONTAINER" nginx -t || true
            docker exec "$NGINX_CONTAINER" nginx -s reload || true
            cleanup_target "$TARGET"
            write_action_output deployment_status FAILED
            exit 1
        }
    done

    verify_proxy "$TARGET" || {
        cp "$BACKUP_FILE" "$DEFAULT_CONF"
        docker exec "$NGINX_CONTAINER" nginx -t || true
        docker exec "$NGINX_CONTAINER" nginx -s reload || true
        cleanup_target "$TARGET"
        write_action_output deployment_status FAILED
        exit 1
    }

    echo "Stabilization check $check/$checks: OK"
    sleep "$CHECK_INTERVAL_SECONDS"
done

echo "[7/7] Stop inactive $SERVICE_NAME $CURRENT containers"
sleep "$DRAIN_SECONDS"

docker rm -f \
    "myapp-$SERVICE_NAME-$CURRENT-1" \
    "myapp-$SERVICE_NAME-$CURRENT-2" \
    2>/dev/null || true

rm -f "$BACKUP_FILE"

write_action_output deployment_status SUCCESS

docker ps --filter "name=myapp-$SERVICE_NAME-" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

echo "$SERVICE_NAME deployment complete: $CURRENT -> $TARGET"