#!/usr/bin/env bash
set -Eeuo pipefail

CURRENT="${1:-}"
FAILED_NEW="${2:-}"

if [ -z "$CURRENT" ]; then
  echo "Usage: rollback-member.sh <current-color> [failed-new-color]"
  exit 1
fi

echo "ROLLBACK TO: $CURRENT"

docker start "myapp-member-$CURRENT-1" "myapp-member-$CURRENT-2" || true

./scripts/replace-nginx-upstream.sh member "$CURRENT" 8080 2

if [ -n "$FAILED_NEW" ]; then
  docker rm -f "myapp-member-$FAILED_NEW-1" "myapp-member-$FAILED_NEW-2" || true
fi

echo "$CURRENT" > /home/um/myApp-Infra/runtime/member-color

echo "ROLLBACK DONE"
