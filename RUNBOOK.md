# myApp Infra Runbook

이 문서는 운영 서버에서 배포 상태를 확인하고, 장애가 났을 때 빠르게 복구하기 위한 절차서다.

## 기본 위치

```bash
cd /home/um/myApp-Infra
```

## 1. 현재 운영 상태 확인

가장 먼저 실행할 명령어다.

```bash
./scripts/check-runtime-state.sh
```

정상 기준:

- `nginx -t` 성공
- Board active color 확인 성공
- Board active container 2대 직접 `/hc` 성공
- Board `/board/hc` 프록시 응답 성공
- Member active color 확인 성공
- Member active container 2대 직접 `/hc` 성공
- Member `/member/hc` 프록시 응답 성공
- `myapp-nginx`가 `0.0.0.0:80->80/tcp` 상태로 실행 중

## 2. Nginx 시작 또는 재검증

Nginx를 시작하거나, 현재 upstream 기준으로 Board/Member 라우팅까지 확인한다.

```bash
./scripts/start-nginx.sh
```

이 명령은 현재 upstream 파일이 가리키는 active color의 컨테이너가 실제로 떠 있어야 성공한다.

## 3. Nginx 설정만 다시 로드

Nginx 설정 파일을 수정했지만 서비스 컨테이너를 새로 배포하지 않는 경우 사용한다.

```bash
./scripts/reload-nginx.sh
```

수행 내용:

- Nginx 설정 문법 검사
- Nginx reload
- `/board/hc`, `/member/hc` 확인

## 4. 수동 트래픽 전환

수동 전환은 대상 color 컨테이너 2대가 이미 떠 있을 때만 사용한다.

### Board 전환

```bash
./scripts/promote-board-upstream.sh blue
./scripts/promote-board-upstream.sh green
```

### Member 전환

```bash
./scripts/promote-member-upstream.sh blue
./scripts/promote-member-upstream.sh green
```

전환 스크립트는 다음을 수행한다.

- 대상 컨테이너 2대 직접 health check
- upstream 파일 변경
- Nginx 설정 검사
- Nginx reload
- 프록시 `/hc` 응답 검증
- 안정화 시간 동안 반복 확인
- 실패 시 이전 upstream으로 자동 rollback 시도

## 5. 배포 실패 시 확인 순서

1. GitHub Actions summary 확인
2. Slack 알림 확인
3. 서버 배포 로그 확인

Board:

```bash
ls -lt /home/um/myapp-deploy-logs/board
tail -n 200 /home/um/myapp-deploy-logs/board/deploy-*.log
```

Member:

```bash
ls -lt /home/um/myapp-deploy-logs/member
tail -n 200 /home/um/myapp-deploy-logs/member/deploy-*.log
```

4. 현재 runtime 상태 확인

```bash
./scripts/check-runtime-state.sh
```

## 6. 컨테이너 직접 확인

```bash
docker ps --filter 'name=myapp-' \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Board 로그:

```bash
docker logs --tail 200 myapp-board-blue-1
docker logs --tail 200 myapp-board-blue-2
docker logs --tail 200 myapp-board-green-1
docker logs --tail 200 myapp-board-green-2
```

Member 로그:

```bash
docker logs --tail 200 myapp-member-blue-1
docker logs --tail 200 myapp-member-blue-2
docker logs --tail 200 myapp-member-green-1
docker logs --tail 200 myapp-member-green-2
```

Nginx 로그:

```bash
docker logs --tail 200 myapp-nginx
```

## 7. 정상 운영 판단 기준

정상 운영 상태는 다음과 같다.

- Board는 blue 또는 green 중 한 color의 2개 컨테이너가 active
- Member는 blue 또는 green 중 한 color의 2개 컨테이너가 active
- Nginx는 active color로만 트래픽 전달
- `/board/hc` 응답의 `env`가 Board active color와 일치
- `/member/hc` 응답의 `env`가 Member active color와 일치

최종 확인 명령:

```bash
./scripts/check-runtime-state.sh
```

## 8. 디스크 사용량 점검

Docker 이미지와 로그가 쌓이면 디스크가 먼저 위험해질 수 있다.

```bash
./scripts/check-disk-usage.sh
```

기본 경고 기준은 루트 파일시스템 사용량 `80%`다. 기준을 바꾸려면 다음처럼 실행한다.

```bash
WARN_PERCENT=70 ./scripts/check-disk-usage.sh
```

확인 항목:

- `/` 파일시스템 사용량
- Docker 전체 디스크 사용량
- `myapp-board`, `myapp-member` 이미지 개수
- 실행 중인 myApp 컨테이너 목록

디스크가 부족할 때 우선 확인할 명령:

```bash
docker system df
docker image ls myapp-board
docker image ls myapp-member
```

## 9. 서버 Git 동기화 확인

운영 서버에는 다음 3개 repo가 있다.

| Repo | 역할 |
| --- | --- |
| `/home/um/myApp-Infra` | Nginx 설정, upstream 전환, 운영 점검 스크립트 |
| `/home/um/myApp-Board` | Board 서버 repo 확인용 |
| `/home/um/myApp-Member` | Member 서버 repo 확인용 |

GitHub Actions의 Board/Member 배포는 Actions runner가 checkout한 최신 코드에서 실행된다. 하지만 Infra 전환 스크립트는 `/home/um/myApp-Infra`를 사용하므로, Infra repo는 특히 최신 상태여야 한다.

서버 repo 상태 확인:

```bash
./scripts/check-server-repos.sh
```

정상 기준:

- `Sync: OK`
- `Local changes: none`
- `Behind remote: 0`
- `Ahead of remote: 0`

수동 동기화:

```bash
cd /home/um/myApp-Infra
git pull --ff-only

cd /home/um/myApp-Board
git pull --ff-only

cd /home/um/myApp-Member
git pull --ff-only
```

`git pull`이 로컬 수정 때문에 실패하면 먼저 어떤 파일이 바뀌었는지 확인한다.

```bash
git status
git diff -- <file>
```

운영 중 생성되는 upstream 상태 파일은 Git에 올리지 않는다.

```text
nginx/conf.d/board-upstream.conf
nginx/conf.d/member-upstream.conf
nginx/conf.d/*.backup
nginx/conf.d/*.next
```
