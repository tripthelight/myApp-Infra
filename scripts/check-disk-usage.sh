#!/usr/bin/env bash

set -Eeuo pipefail

WARN_PERCENT="${WARN_PERCENT:-80}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

if [[ ! "$WARN_PERCENT" =~ ^[1-9][0-9]?$|^100$ ]]; then
    echo "WARN_PERCENT must be an integer between 1 and 100." >&2
    exit 1
fi

require_command awk
require_command df
require_command docker

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running or the current user cannot access it." >&2
    exit 1
fi

root_usage="$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"

echo "[1/4] Filesystem usage"
df -h /

echo
echo "[2/4] Docker disk usage"
docker system df

echo
echo "[3/4] myApp image count"
for image_name in myapp-board myapp-member myapp-front; do
    count="$(docker image ls "$image_name" --format '{{.Repository}}:{{.Tag}}' | wc -l | awk '{print $1}')"
    echo "$image_name images: $count"
done

echo
echo "[4/4] Running myApp containers"
docker ps \
    --filter 'name=myapp-nginx' \
    --filter 'name=myapp-board-' \
    --filter 'name=myapp-member-' \
    --filter 'name=myapp-front-' \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

echo
if [ "$root_usage" -ge "$WARN_PERCENT" ]; then
    echo "Disk usage warning: / is ${root_usage}% used. Threshold is ${WARN_PERCENT}%." >&2
    exit 1
fi

echo "Disk usage OK: / is ${root_usage}% used. Threshold is ${WARN_PERCENT}%."
