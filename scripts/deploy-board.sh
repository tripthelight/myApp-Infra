#!/usr/bin/env bash
set -Eeuo pipefail

INFRA_DIR="/home/um/myApp-Infra"
BOARD_DIR="/home/um/myApp-Board"
BOARD_IMAGE_NAME="myapp-board"
BOARD_IMAGE_TAG="${BOARD_IMAGE_TAG:-local-board-jpa}"
NETWORK_NAME="myapp-network"
COLOR_FILE="/tmp/board-color"
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

cd "$INFRA_DIR"

echo "[1] Detect current board color"

CURRENT="$(cat "$COLOR_FILE" 2>/dev/null || echo "blue")"

if [ "$CURRENT" = "blue" ]; then
  NEW="green"
elif [ "$CURRENT" = "green" ]; then
  NEW="blue"
else
  echo "Invalid current color: $CURRENT"
  exit 1
fi

echo "CURRENT=$CURRENT"
echo "NEW=$NEW"

echo "[2] Load Board DB password"

BOARD_DB_PASSWORD="$(docker exec myapp-mariadb cat /run/secrets/mariadb_root)"

if [ -z "$BOARD_DB_PASSWORD" ]; then
  echo "BOARD_DB_PASSWORD is empty"
  exit 1
fi

echo "[3] Start new board containers"

IMAGE_NAME="$BOARD_IMAGE_NAME" \
IMAGE_TAG="$BOARD_IMAGE_TAG" \
BOARD_DB_PASSWORD="$BOARD_DB_PASSWORD" \
docker compose -f "$BOARD_DIR/deploy/docker-compose-$NEW.yml" up -d

echo "[4] Health check new board containers"

for SERVER in "myapp-board-$NEW-1" "myapp-board-$NEW-2"; do
  echo "Checking $SERVER:8080"

  OK="false"

  for i in $(seq 1 30); do
    if docker run --rm --network "$NETWORK_NAME" busybox:1.36 \
      nc -z -w 2 "$SERVER" 8080 >/dev/null 2>&1; then
      OK="true"
      echo "$SERVER OK"
      break
    fi

    echo "$SERVER waiting... $i"
    sleep 2
  done

  if [ "$OK" != "true" ]; then
    echo "$SERVER health check failed"
    ./scripts/rollback-board.sh "$CURRENT" "$NEW"
    exit 1
  fi
done

echo "[5] Switch only nginx board upstream"

replace_board_upstream "$NEW"

docker exec myapp-nginx nginx -t
docker exec myapp-nginx nginx -s reload

echo "$NEW" > "$COLOR_FILE"

echo "[6] Stop old board containers"

docker rm -f "myapp-board-$CURRENT-1" "myapp-board-$CURRENT-2" || true

echo "DEPLOY SUCCESS: board $CURRENT -> $NEW"
