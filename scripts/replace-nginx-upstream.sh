#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-}"
COLOR="${2:-}"
PORT="${3:-}"
COUNT="${4:-2}"
NGINX_CONF="${NGINX_CONF:-/home/um/myApp-Infra/nginx/conf.d/default.conf}"

if [ -z "$SERVICE" ] || [ -z "$COLOR" ] || [ -z "$PORT" ]; then
  echo "Usage: replace-nginx-upstream.sh <service> <color> <port> [count]"
  exit 1
fi

if [ "$COLOR" != "blue" ] && [ "$COLOR" != "green" ]; then
  echo "Invalid color: $COLOR"
  exit 1
fi

if [ ! -f "$NGINX_CONF" ]; then
  echo "Nginx config not found: $NGINX_CONF"
  exit 1
fi

BACKUP_FILE="${NGINX_CONF}.backup"
TMP_FILE="$(mktemp)"

cp "$NGINX_CONF" "$BACKUP_FILE"

awk -v service="$SERVICE" -v color="$COLOR" -v port="$PORT" -v count="$COUNT" '
  BEGIN { in_target = 0 }

  $0 ~ "^upstream " service "[[:space:]]*\\{" {
    print "upstream " service " {"
    for (i = 1; i <= count; i++) {
      print "    server myapp-" service "-" color "-" i ":" port ";"
    }
    print "}"
    in_target = 1
    next
  }

  in_target == 1 && /^\}/ {
    in_target = 0
    next
  }

  in_target == 0 {
    print
  }
' "$NGINX_CONF" > "$TMP_FILE"

cp "$TMP_FILE" "$NGINX_CONF"
rm -f "$TMP_FILE"

if ! docker exec myapp-nginx nginx -t; then
  echo "Nginx test failed. Restoring backup."
  cp "$BACKUP_FILE" "$NGINX_CONF"
  docker exec myapp-nginx nginx -t || true
  exit 1
fi

docker exec myapp-nginx nginx -s reload

echo "Updated upstream $SERVICE -> $COLOR"
