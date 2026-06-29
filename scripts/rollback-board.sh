#!/bin/bash

OLD=$1

echo "ROLLBACK TO: $OLD"

./scripts/switch-board-upstream.sh "$OLD"

docker start myapp-board-$OLD-1 || true
docker start myapp-board-$OLD-2 || true

echo "ROLLBACK DONE"