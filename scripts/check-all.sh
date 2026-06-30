#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_check() {
    title="$1"
    script="$2"

    echo
    echo "================================================================"
    echo "$title"
    echo "================================================================"

    "$script"
}

echo "myApp operation check started at $(date '+%Y-%m-%dT%H:%M:%S%z')"

run_check "[1/3] Server repository sync" "$PROJECT_DIR/scripts/check-server-repos.sh"
run_check "[2/3] Runtime state" "$PROJECT_DIR/scripts/check-runtime-state.sh"
run_check "[3/3] Disk usage" "$PROJECT_DIR/scripts/check-disk-usage.sh"

echo
echo "================================================================"
echo "myApp operation check complete."
echo "================================================================"
