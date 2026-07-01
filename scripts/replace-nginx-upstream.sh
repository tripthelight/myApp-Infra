#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-}"
COLOR="${2:-}"
PORT="${3:-}"
COUNT="${4:-2}"
NGINX_CONF="${NGINX_CONF:-/home/um/myApp-Nginx/conf.d/default.conf}"

if [ -z "$SERVICE" ] || [ -z "$COLOR" ] || [ -z "$PORT" ]; then
  echo "Usage: replace-nginx-upstream.sh <service> <color> <port> [count]"
  exit 1
fi

if [ ! -f "$NGINX_CONF" ]; then
  echo "Nginx config not found: $NGINX_CONF"
  exit 1
fi

tmp_file="$(mktemp)"

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
' "$NGINX_CONF" > "$tmp_file"

cp "$NGINX_CONF" "$NGINX_CONF.backup"
mv "$tmp_file" "$NGINX_CONF"

docker exec myapp-nginx nginx -t
docker exec myapp-nginx nginx -s reload

echo "Updated upstream $SERVICE -> $COLOR"
