#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT="${1:-}"
FAILED_NEW="${2:-}"

if [ -z "$CURRENT" ]; then
  echo "Usage: rollback-front.sh <current-color> [failed-new-color]"
  exit 1
fi

echo "ROLLBACK TO: $CURRENT"

docker start "myapp-front-$CURRENT-1" "myapp-front-$CURRENT-2" || true

./scripts/replace-nginx-upstream.sh front "$CURRENT" 80 2

if [ -n "$FAILED_NEW" ]; then
  docker rm -f "myapp-front-$FAILED_NEW-1" "myapp-front-$FAILED_NEW-2" || true
fi

echo "$CURRENT" > /home/um/myApp-Infra/runtime/front-color

echo "ROLLBACK DONE"
