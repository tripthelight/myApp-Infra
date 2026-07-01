#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT="${1:-}"
FAILED_NEW="${2:-}"
NGINX_CONF="/home/um/myApp-Nginx/conf.d/default.conf"

replace_board_upstream() {
  local color="$1"
  local tmp_file

  tmp_file="$(mktemp)"

  awk -v color="$color" '
    BEGIN { in_board = 0 }

    /^upstream board[[:space:]]*\{/ {
      print "upstream board {"
      print "    server myapp-board-" color "-1:8080;"
      print "    server myapp-board-" color "-2:8080;"
      print "}"
      in_board = 1
      next
    }

    in_board == 1 && /^\}/ {
      in_board = 0
      next
    }

    in_board == 0 {
      print
    }
  ' "$NGINX_CONF" > "$tmp_file"

  cp "$NGINX_CONF" "$NGINX_CONF.backup"
  mv "$tmp_file" "$NGINX_CONF"
}

if [ -z "$CURRENT" ]; then
  echo "Usage: rollback-board.sh <current-color> [failed-new-color]"
  exit 1
fi

echo "ROLLBACK TO: $CURRENT"

docker start "myapp-board-$CURRENT-1" "myapp-board-$CURRENT-2" || true

replace_board_upstream "$CURRENT"

docker exec myapp-nginx nginx -t
docker exec myapp-nginx nginx -s reload

if [ -n "$FAILED_NEW" ]; then
  docker rm -f "myapp-board-$FAILED_NEW-1" "myapp-board-$FAILED_NEW-2" || true
fi

echo "$CURRENT" > /tmp/board-color

echo "ROLLBACK DONE"
