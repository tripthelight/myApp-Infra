#!/usr/bin/env bash
set -Eeuo pipefail

INFRA_DIR="/home/um/myApp-Infra"
NETWORK_NAME="myapp-network"
COLOR_FILE="/tmp/front-color"
SERVICE="front"
PORT="80"

cd "$INFRA_DIR"

echo "[1] Detect current front color"

CURRENT="$(cat "$COLOR_FILE" 2>/dev/null || echo "green")"

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

SOURCE_CONTAINER="myapp-front-$CURRENT-1"

if ! docker inspect "$SOURCE_CONTAINER" >/dev/null 2>&1; then
  echo "Source container not found: $SOURCE_CONTAINER"
  exit 1
fi

IMAGE="$(docker inspect -f '{{.Config.Image}}' "$SOURCE_CONTAINER")"
ENV_FILE="$(mktemp)"

docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$SOURCE_CONTAINER" > "$ENV_FILE"

echo "[2] Start new front containers with image: $IMAGE"

docker rm -f "myapp-front-$NEW-1" "myapp-front-$NEW-2" >/dev/null 2>&1 || true

docker run -d \
  --name "myapp-front-$NEW-1" \
  --network "$NETWORK_NAME" \
  --env-file "$ENV_FILE" \
  "$IMAGE"

docker run -d \
  --name "myapp-front-$NEW-2" \
  --network "$NETWORK_NAME" \
  --env-file "$ENV_FILE" \
  "$IMAGE"

rm -f "$ENV_FILE"

echo "[3] Health check new front containers"

for SERVER in "myapp-front-$NEW-1" "myapp-front-$NEW-2"; do
  echo "Checking $SERVER:$PORT"

  OK="false"

  for i in $(seq 1 30); do
    if docker run --rm --network "$NETWORK_NAME" busybox:1.36 \
      nc -z -w 2 "$SERVER" "$PORT" >/dev/null 2>&1; then
      OK="true"
      echo "$SERVER OK"
      break
    fi

    echo "$SERVER waiting... $i"
    sleep 2
  done

  if [ "$OK" != "true" ]; then
    echo "$SERVER health check failed"
    ./scripts/rollback-front.sh "$CURRENT" "$NEW"
    exit 1
  fi
done

echo "[4] Switch nginx front upstream"

./scripts/replace-nginx-upstream.sh "$SERVICE" "$NEW" "$PORT" 2

echo "$NEW" > "$COLOR_FILE"

echo "[5] Stop old front containers"

docker rm -f "myapp-front-$CURRENT-1" "myapp-front-$CURRENT-2" || true

echo "DEPLOY SUCCESS: front $CURRENT -> $NEW"
