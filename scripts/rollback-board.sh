#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT="${1:-}"
FAILED_NEW="${2:-}"

if [ -z "$CURRENT" ]; then
  echo "Usage: rollback-board.sh <current-color> [failed-new-color]"
  exit 1
fi

echo "ROLLBACK TO: $CURRENT"

./scripts/switch-board-upstream.sh "$CURRENT"

docker start "myapp-board-$CURRENT-1" "myapp-board-$CURRENT-2" || true

if [ -n "$FAILED_NEW" ]; then
  docker rm -f "myapp-board-$FAILED_NEW-1" "myapp-board-$FAILED_NEW-2" || true
fi

echo "$CURRENT" > /tmp/board-color

echo "ROLLBACK DONE"
