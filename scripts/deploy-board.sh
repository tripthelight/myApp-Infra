#!/bin/bash

set +e

echo "[1] Detect current color"

CURRENT=$(cat /tmp/board-color || echo "blue")

if [ "$CURRENT" = "blue" ]; then
  NEW="green"
else
  NEW="blue"
fi

echo "[2] Deploy new color: $NEW"

docker compose -f compose.yml up -d board-$NEW-1 board-$NEW-2

echo "[3] Health check"

for i in {1..15}; do
  sleep 2

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  http://127.0.0.1/board/hc || echo "FAIL")

  if [ "$STATUS" != "200" ]; then
    echo "FAIL DETECTED → ROLLBACK"

    ./scripts/rollback-board.sh "$CURRENT"
    exit 1
  fi

  echo "check $i OK"
done

echo "[4] Switch nginx"

./scripts/switch-board-upstream.sh "$NEW"

echo "$NEW" > /tmp/board-color

echo "[5] Stop old containers"

docker rm -f board-$CURRENT-1 || true
docker rm -f board-$CURRENT-2 || true

echo "DEPLOY SUCCESS"