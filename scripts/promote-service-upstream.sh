#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONTAINER="myapp-nginx"
SERVICE_NAME="${1:-}"
TARGET="${2:-}"
STABILIZATION_SECONDS="${STABILIZATION_SECONDS:-30}"
CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-2}"
ROLLBACK_TEST_AFTER_SWITCH="${ROLLBACK_TEST_AFTER_SWITCH:-false}"

usage() {
    echo "Usage: $0 service-name blue|green" >&2
    exit 1
}

[[ "$SERVICE_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || usage
{ [ "$TARGET" = blue ] || [ "$TARGET" = green ]; } || usage

if [[ ! "$STABILIZATION_SECONDS" =~ ^[1-9][0-9]*$ ]] || \
   [[ ! "$CHECK_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Stabilization and check interval values must be positive integers." >&2
    exit 1
fi

if [ "$ROLLBACK_TEST_AFTER_SWITCH" != true ] && \
   [ "$ROLLBACK_TEST_AFTER_SWITCH" != false ]; then
    echo "ROLLBACK_TEST_AFTER_SWITCH must be true or false." >&2
    exit 1
fi

UPSTREAM_FILE="$PROJECT_DIR/nginx/conf.d/$SERVICE_NAME-upstream.conf"
SWITCH_SCRIPT="$PROJECT_DIR/scripts/switch-service-upstream.sh"
CONTAINER_PREFIX="myapp-$SERVICE_NAME"

if [ ! -f "$UPSTREAM_FILE" ]; then
    echo "Upstream state does not exist: $UPSTREAM_FILE" >&2
    exit 1
fi

if grep -Fq "$CONTAINER_PREFIX-blue-1:8080" "$UPSTREAM_FILE"; then
    CURRENT=blue
elif grep -Fq "$CONTAINER_PREFIX-green-1:8080" "$UPSTREAM_FILE"; then
    CURRENT=green
else
    echo "Could not determine the active $SERVICE_NAME color." >&2
    exit 1
fi

if [ "$CURRENT" = "$TARGET" ]; then
    echo "$SERVICE_NAME upstream already uses $TARGET." >&2
    exit 1
fi

rollback() {
    reason="$1"
    echo "Post-switch verification failed: $reason" >&2
    echo "Rolling $SERVICE_NAME upstream back to $CURRENT." >&2

    if "$SWITCH_SCRIPT" "$SERVICE_NAME" "$CURRENT"; then
        echo "Automatic upstream rollback complete: $TARGET -> $CURRENT" >&2
        exit 1
    else
        echo "Automatic upstream rollback failed. Both colors must be inspected." >&2
        exit 2
    fi
}

echo "[1/2] Switch $SERVICE_NAME upstream: $CURRENT -> $TARGET"
"$SWITCH_SCRIPT" "$SERVICE_NAME" "$TARGET"

if [ "$ROLLBACK_TEST_AFTER_SWITCH" = true ]; then
    test_container="$CONTAINER_PREFIX-$TARGET-1"
    echo "[ROLLBACK TEST] Stop $test_container after the Nginx switch."
    docker stop "$test_container" >/dev/null
fi

checks=$(((STABILIZATION_SECONDS + CHECK_INTERVAL_SECONDS - 1) / CHECK_INTERVAL_SECONDS))

echo "[2/2] Stabilize $SERVICE_NAME $TARGET for ${STABILIZATION_SECONDS}s"
for check in $(seq 1 "$checks"); do
    for instance in 1 2; do
        container="$CONTAINER_PREFIX-$TARGET-$instance"

        if ! docker exec "$NGINX_CONTAINER" \
            wget -q -T 2 -O /dev/null "http://$container:8080/hc"; then
            rollback "$container failed its direct health check"
        fi
    done

    response="$(docker exec "$NGINX_CONTAINER" \
        wget -q -T 2 -O - "http://127.0.0.1/$SERVICE_NAME/hc" || true)"

    if ! grep -Fq "\"env\":\"$TARGET\"" <<< "$response"; then
        rollback "unexpected proxy response: $response"
    fi

    echo "Stabilization check $check/$checks: OK"
    sleep "$CHECK_INTERVAL_SECONDS"
done

echo "$SERVICE_NAME promotion complete: $CURRENT -> $TARGET"
