#!/usr/bin/env bash
set -e

############################################
# CONFIG
############################################
APP_NAME="myapp-board"

BLUE_PORT=9090
GREEN_PORT=9091

HEALTH_ENDPOINT="/env"
HEALTH_TIMEOUT=60
HEALTH_INTERVAL=2

JAR="/home/um/myapp/app.jar"
NGINX_UPSTREAM="/etc/nginx/conf.d/upstream.conf"

SLACK_WEBHOOK="https://hooks.slack.com/services/XXX/YYY/ZZZ"
LOG_FILE="/home/um/myapp/deploy.log"

############################################
# LOGGING
############################################
exec > >(tee -a $LOG_FILE) 2>&1

############################################
# SLACK FUNCTION
############################################
send_slack () {
  local STATUS=$1
  local MESSAGE=$2

  curl -s -X POST -H 'Content-type: application/json' \
    --data "{
      \"text\": \"[$STATUS] $MESSAGE\"
    }" \
    $SLACK_WEBHOOK > /dev/null
}

trap 'send_slack "ERROR" "💥 배포 중 예외 발생 (강제 종료)"' ERR

############################################
# DETECT CURRENT STATE
############################################
echo "🔍 현재 상태 확인..."

CURRENT=$(curl -s http://localhost${HEALTH_ENDPOINT} || echo "blue")

if [[ "$CURRENT" == "blue" ]]; then
  ACTIVE_PORT=$BLUE_PORT
  STANDBY_PORT=$GREEN_PORT
  TARGET="green"
else
  ACTIVE_PORT=$GREEN_PORT
  STANDBY_PORT=$BLUE_PORT
  TARGET="blue"
fi

echo "👉 ACTIVE: $ACTIVE_PORT"
echo "👉 TARGET: $TARGET ($STANDBY_PORT)"

############################################
# STOP OLD STANDBY
############################################
echo "🧹 standby 정리..."
fuser -k ${STANDBY_PORT}/tcp || true

############################################
# START NEW VERSION
############################################
echo "🚀 새 버전 실행..."

nohup java -jar \
  -Dserver.port=${STANDBY_PORT} \
  -Dspring.profiles.active=${TARGET} \
  ${JAR} > ${TARGET}.log 2>&1 &

NEW_PID=$!

############################################
# HEALTH CHECK
############################################
echo "⏳ Health Check 시작..."

START=$(date +%s)
OK=false

while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:${STANDBY_PORT}${HEALTH_ENDPOINT} || true)

  if [[ "$CODE" == "200" ]]; then
    OK=true
    break
  fi

  NOW=$(date +%s)
  if (( NOW - START > HEALTH_TIMEOUT )); then
    break
  fi

  sleep $HEALTH_INTERVAL
done

############################################
# FAIL → ROLLBACK
############################################
if [[ "$OK" != true ]]; then

  echo "❌ 배포 실패 → 롤백"

  kill -9 $NEW_PID || true

  send_slack "FAIL" "❌ 배포 실패 (ROLLBACK 발생) - $TARGET"

  exit 1
fi

###############################################
# SUCCESS → SWITCH TRAFFIC
###############################################
echo "🔀 트래픽 전환..."

cat <<EOF > /tmp/upstream.conf
upstream myapp {
    server 127.0.0.1:${STANDBY_PORT};
}
EOF

sudo cp /tmp/upstream.conf ${NGINX_UPSTREAM}
sudo nginx -s reload

send_slack "SUCCESS" "🚀 배포 성공: $TARGET ($STANDBY_PORT)"

############################################
# GRACEFUL SHUTDOWN OLD SERVER
############################################
echo "⏳ 기존 서버 종료 대기..."
sleep 10

fuser -k ${ACTIVE_PORT}/tcp || true

############################################
# FINAL STATE
############################################
echo "🎉 배포 완료!"
echo "ACTIVE: $TARGET ($STANDBY_PORT)"