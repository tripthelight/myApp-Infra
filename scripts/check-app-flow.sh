#!/usr/bin/env bash

set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1}"
TEST_USERNAME="${TEST_USERNAME:-testuser}"
TEST_PASSWORD="${TEST_PASSWORD:-test1234}"

CREATED_BOARD_ID=""

print_step() {
    echo
    echo "===== $1 ====="
}

fail() {
    echo
    echo "FAILED: $1" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "Required command not found: $1"
    fi
}

http_status() {
    method="$1"
    url="$2"
    body="${3:-}"

    if [ -n "$body" ]; then
        curl -s -o /tmp/myapp-flow-response.txt -w "%{http_code}" \
            -X "$method" \
            -H "Content-Type: application/json" \
            -d "$body" \
            "$url"
    else
        curl -s -o /tmp/myapp-flow-response.txt -w "%{http_code}" \
            -X "$method" \
            "$url"
    fi
}

response_body() {
    cat /tmp/myapp-flow-response.txt
}

assert_status_2xx() {
    status="$1"
    label="$2"

    case "$status" in
        2*) echo "OK: $label ($status)" ;;
        *)  echo "Response body:"
            response_body
            fail "$label returned HTTP $status"
            ;;
    esac
}

assert_contains() {
    text="$1"
    expected="$2"
    label="$3"

    if grep -Fq "$expected" <<< "$text"; then
        echo "OK: $label"
    else
        echo "Actual response:"
        printf '%s\n' "$text"
        fail "$label does not contain: $expected"
    fi
}

extract_json_id() {
    python3 - "$1" <<'PY'
import json
import sys

raw = sys.argv[1]

try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

value = data.get("id")
print("" if value is None else value)
PY
}

cleanup_created_board() {
    if [ -n "${CREATED_BOARD_ID:-}" ]; then
        echo
        echo "Cleanup created board id=$CREATED_BOARD_ID"

        status="$(http_status DELETE "$BASE_URL/board/$CREATED_BOARD_ID")"

        case "$status" in
            2*|404)
                echo "Cleanup OK: HTTP $status"
                ;;
            *)
                echo "Cleanup response body:"
                response_body
                echo "Cleanup WARN: HTTP $status" >&2
                ;;
        esac
    fi
}

trap cleanup_created_board EXIT

require_command curl
require_command python3

print_step "1. Nginx and service health check"

status="$(http_status GET "$BASE_URL/")"
assert_status_2xx "$status" "Front proxy /"

status="$(http_status GET "$BASE_URL/member/hc")"
assert_status_2xx "$status" "Member proxy /member/hc"
member_body="$(response_body)"
assert_contains "$member_body" '"env"' "Member health response has env"

status="$(http_status GET "$BASE_URL/board/hc")"
assert_status_2xx "$status" "Board proxy /board/hc"
board_body="$(response_body)"
assert_contains "$board_body" '"env"' "Board health response has env"

print_step "2. Login API check"

login_success="false"

login_payloads=(
    "{\"username\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}"
    "{\"loginId\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}"
    "{\"userId\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}"
    "{\"email\":\"$TEST_USERNAME\",\"password\":\"$TEST_PASSWORD\"}"
)

for payload in "${login_payloads[@]}"; do
    status="$(http_status POST "$BASE_URL/member/login" "$payload")"

    if [[ "$status" =~ ^2 ]]; then
        echo "OK: Login API /member/login ($status)"
        login_success="true"
        break
    fi
done

if [ "$login_success" != "true" ]; then
    echo "Last login response body:"
    response_body
    fail "Login API failed for all supported payloads"
fi

print_step "3. Board list check"

status="$(http_status GET "$BASE_URL/board/list")"
assert_status_2xx "$status" "Board list /board/list"

list_body="$(response_body)"
assert_contains "$list_body" "[" "Board list returns JSON array"

print_step "4. Board create check"

unique_suffix="$(date +%Y%m%d%H%M%S)"
create_title="자동 회귀 테스트 등록 $unique_suffix"
create_content="check-app-flow.sh create test"
create_writer="$TEST_USERNAME"

create_payload="$(python3 - "$create_title" "$create_content" "$create_writer" <<'PY'
import json
import sys

print(json.dumps({
    "title": sys.argv[1],
    "content": sys.argv[2],
    "writer": sys.argv[3],
}, ensure_ascii=False))
PY
)"

status="$(http_status POST "$BASE_URL/board/write" "$create_payload")"
assert_status_2xx "$status" "Board create /board/write"

create_body="$(response_body)"
CREATED_BOARD_ID="$(extract_json_id "$create_body")"

if [ -z "$CREATED_BOARD_ID" ]; then
    echo "Create response body:"
    printf '%s\n' "$create_body"
    fail "Created board id was not found"
fi

echo "OK: Created board id=$CREATED_BOARD_ID"

status="$(http_status GET "$BASE_URL/board/list")"
assert_status_2xx "$status" "Board list after create"
list_after_create="$(response_body)"
assert_contains "$list_after_create" "$create_title" "Created board appears in list"

print_step "5. Board detail check"

status="$(http_status GET "$BASE_URL/board/$CREATED_BOARD_ID")"
assert_status_2xx "$status" "Board detail /board/$CREATED_BOARD_ID"

detail_body="$(response_body)"
assert_contains "$detail_body" "$create_title" "Board detail contains created title"

print_step "6. Board update check"

update_title="자동 회귀 테스트 수정 $unique_suffix"
update_content="check-app-flow.sh update test"

update_payload="$(python3 - "$update_title" "$update_content" "$create_writer" <<'PY'
import json
import sys

print(json.dumps({
    "title": sys.argv[1],
    "content": sys.argv[2],
    "writer": sys.argv[3],
}, ensure_ascii=False))
PY
)"

status="$(http_status PUT "$BASE_URL/board/$CREATED_BOARD_ID" "$update_payload")"
assert_status_2xx "$status" "Board update /board/$CREATED_BOARD_ID"

update_body="$(response_body)"
assert_contains "$update_body" "$update_title" "Update response contains updated title"

status="$(http_status GET "$BASE_URL/board/list")"
assert_status_2xx "$status" "Board list after update"
list_after_update="$(response_body)"
assert_contains "$list_after_update" "$update_title" "Updated board appears in list"

print_step "7. Board container consistency check"

active_board_containers="$(
    docker ps \
        --filter 'name=myapp-board-' \
        --format '{{.Names}}' \
        | sort
)"

container_count="$(printf '%s\n' "$active_board_containers" | sed '/^$/d' | wc -l | tr -d ' ')"

if [ "$container_count" -lt 2 ]; then
    printf '%s\n' "$active_board_containers"
    fail "Expected at least 2 running board containers"
fi

for container in $active_board_containers; do
    direct_body="$(docker exec myapp-nginx wget -q -T 2 -O - "http://$container:8080/list")"
    assert_contains "$direct_body" "$update_title" "$container sees updated board"
done

print_step "8. Board delete check"

status="$(http_status DELETE "$BASE_URL/board/$CREATED_BOARD_ID")"
assert_status_2xx "$status" "Board delete /board/$CREATED_BOARD_ID"

CREATED_BOARD_ID=""

status="$(http_status GET "$BASE_URL/board/list")"
assert_status_2xx "$status" "Board list after delete"
list_after_delete="$(response_body)"

if grep -Fq "$update_title" <<< "$list_after_delete"; then
    echo "Actual response:"
    printf '%s\n' "$list_after_delete"
    fail "Deleted board still appears in list"
fi

echo "OK: Deleted board disappeared from list"

print_step "9. Final runtime state"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -x "$SCRIPT_DIR/check-runtime-state.sh" ]; then
    "$SCRIPT_DIR/check-runtime-state.sh"
else
    echo "WARN: check-runtime-state.sh is not executable or not found"
fi

echo
echo "Application flow check complete."