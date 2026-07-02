# myApp Infra RUNBOOK

이 문서는 `myApp` 서비스의 배포 구조, 상태 확인, 수동 배포, Nginx 복구, MariaDB 확인, 장애 상황별 복구 절차를 정리한 운영 문서이다.

이 문서는 `myApp-Infra` 저장소 기준으로 관리한다.

---

## 1. 현재 배포 구조

현재 배포 흐름은 다음과 같다.

```text
Windows 개발 PC
  ↓
git push
  ↓
GitHub Actions
  ↓
Ubuntu VM self-hosted runner
  ↓
Docker image build
  ↓
blue/green 새 컨테이너 2개 실행
  ↓
Nginx upstream 전환
  ↓
이전 color 컨테이너 제거
  ↓
자동 회귀 테스트 실행
```

서비스는 다음 저장소로 분리되어 있다.

```text
myApp-Infra   : Nginx, 배포 스크립트, 검증 스크립트
myApp-Front   : 프론트엔드
myApp-Member  : 회원 / 로그인 API
myApp-Board   : 게시판 API
```

Ubuntu VM 기준 저장소 위치는 다음과 같다.

```bash
/home/um/myApp-Infra
/home/um/myApp-Front
/home/um/myApp-Member
/home/um/myApp-Board
```

---

## 2. 현재 핵심 런타임 구성

현재 운영 구조는 다음과 같다.

```text
Nginx 컨테이너:
  myapp-nginx

Docker network:
  myapp-network

Front 컨테이너:
  myapp-front-blue-1
  myapp-front-blue-2
  myapp-front-green-1
  myapp-front-green-2

Member 컨테이너:
  myapp-member-blue-1
  myapp-member-blue-2
  myapp-member-green-1
  myapp-member-green-2

Board 컨테이너:
  myapp-board-blue-1
  myapp-board-blue-2
  myapp-board-green-1
  myapp-board-green-2

MariaDB 컨테이너:
  myapp-mariadb
```

주의할 점은 blue/green 현재 활성 상태를 문서에 고정하지 않는 것이다.

현재 활성 color는 항상 아래 파일에서 판단한다.

```bash
/home/um/myApp-Infra/nginx/conf.d/default.conf
```

또는 아래 스크립트로 확인한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
```

---

## 3. Nginx 설정 구조

현재 실제 Nginx runtime 설정 파일은 다음 파일이다.

```bash
/home/um/myApp-Infra/nginx/conf.d/default.conf
```

이 파일은 런타임 상태 파일이다.

Git 추적 대상에서 제외되어 있다.

```text
nginx/conf.d/default.conf
```

기본 템플릿 파일은 다음 파일이다.

```bash
/home/um/myApp-Infra/nginx/templates/default.conf
```

Nginx 복구 스크립트는 다음 파일이다.

```bash
/home/um/myApp-Infra/scripts/start-nginx.sh
```

현재 배포 스크립트는 `nginx/conf.d/default.conf` 안의 아래 upstream block을 직접 교체한다.

```nginx
upstream front {
    server myapp-front-blue-1:80;
    server myapp-front-blue-2:80;
}

upstream member {
    server myapp-member-blue-1:8080;
    server myapp-member-blue-2:8080;
}

upstream board {
    server myapp-board-blue-1:8080;
    server myapp-board-blue-2:8080;
}
```

Front는 컨테이너 내부 포트 `80`을 사용한다.

Member와 Board는 컨테이너 내부 포트 `8080`을 사용한다.

```text
Front  : 80
Member : 8080
Board  : 8080
```

---

## 4. 가장 먼저 실행해야 하는 정상 상태 확인

Ubuntu VM에서 실행한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
```

정상이라면 다음 항목이 성공해야 한다.

```text
Nginx 설정 문법 검사 성공
Front active color 확인 성공
Front active 컨테이너 2개 direct health check 성공
Front proxy check 성공
Member active color 확인 성공
Member active 컨테이너 2개 direct health check 성공
Member proxy /member/hc 성공
Board active color 확인 성공
Board active 컨테이너 2개 direct health check 성공
Board proxy /board/hc 성공
Runtime state check complete.
```

전체 애플리케이션 회귀 테스트는 다음 명령어로 실행한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-app-flow.sh
```

정상이라면 다음 흐름이 성공해야 한다.

```text
Front proxy / 성공
Member proxy /member/hc 성공
Board proxy /board/hc 성공
Login API 성공
Board list 성공
Board create 성공
Board detail 성공
Board update 성공
Board container consistency 성공
Board delete 성공
Application flow check complete.
```

---

## 5. Docker 상태 확인

현재 실행 중인 컨테이너를 확인한다.

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

전체 컨테이너를 확인한다.

```bash
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

myApp 관련 컨테이너만 확인한다.

```bash
docker ps -a \
  --filter "name=myapp-" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

Nginx 컨테이너만 확인한다.

```bash
docker ps \
  --filter "name=myapp-nginx" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

---

## 6. 현재 active color 확인

현재 active color는 `nginx/conf.d/default.conf`에서 확인한다.

```bash
cd /home/um/myApp-Infra
grep -n "server myapp-" nginx/conf.d/default.conf
```

예시:

```text
server myapp-front-green-1:80;
server myapp-front-green-2:80;
server myapp-member-blue-1:8080;
server myapp-member-blue-2:8080;
server myapp-board-green-1:8080;
server myapp-board-green-2:8080;
```

위 예시는 다음 의미이다.

```text
Front  : green
Member : blue
Board  : green
```

컨테이너 상태까지 함께 보려면 다음 명령어를 실행한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
```

---

## 7. GitHub Actions 자동 배포

일반 배포는 수동 명령이 아니라 GitHub Actions로 수행한다.

### Front 자동 배포

저장소:

```text
myApp-Front
```

Workflow:

```text
.github/workflows/CICD.yml
```

Trigger:

```text
push to main
workflow_dispatch
```

현재 흐름:

```text
Checkout
  ↓
Verify deployment environment
  ↓
./scripts/deploy-local.sh
  ↓
Front Docker image build
  ↓
myApp-Infra/scripts/deploy-front.sh 실행
  ↓
myApp-Infra/scripts/check-app-flow.sh 실행
```

### Member 자동 배포

저장소:

```text
myApp-Member
```

Workflow:

```text
.github/workflows/deploy-local.yml
```

Trigger:

```text
push to main
workflow_dispatch
```

현재 흐름:

```text
Checkout
  ↓
Verify deployment environment
  ↓
./mvnw clean package -DskipTests
  ↓
docker build
  ↓
IMAGE_OVERRIDE="myapp-member:${GITHUB_SHA}" ./scripts/deploy-member.sh
  ↓
myApp-Infra/scripts/check-app-flow.sh 실행
```

### Board 자동 배포

저장소:

```text
myApp-Board
```

Workflow:

```text
.github/workflows/CICD.yml
```

Trigger:

```text
push to main
workflow_dispatch
```

현재 흐름:

```text
Checkout
  ↓
Set up Java 17
  ↓
Verify deployment environment
  ↓
./mvnw -DskipTests clean package
  ↓
docker build --tag "myapp-board:${GITHUB_SHA}" .
  ↓
IMAGE_OVERRIDE="myapp-board:${GITHUB_SHA}" ./scripts/deploy-board.sh
  ↓
myApp-Infra/scripts/check-app-flow.sh 실행
```

---

## 8. 자동 배포 후 필수 확인

GitHub Actions 배포가 성공한 뒤 Ubuntu VM에서 아래 명령어를 실행한다.

```bash
cd /home/um/myApp-Infra
git pull --ff-only origin main
chmod +x scripts/*.sh
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

브라우저에서도 확인한다.

```text
http://127.0.0.1:8080/
http://localhost:5173/
```

확인할 기능은 다음과 같다.

```text
로그인
게시글 목록 조회
게시글 상세 조회
게시글 등록
게시글 수정
게시글 삭제
```

---

## 9. 수동 배포 원칙

수동 배포는 다음 경우에만 사용한다.

```text
GitHub Actions 장애
self-hosted runner 장애
GitHub Actions workflow 수정 전 긴급 확인
로컬 Ubuntu VM에서 직접 배포 테스트가 필요한 경우
```

현재 `myApp-Infra/scripts/deploy-front.sh`, `deploy-member.sh`, `deploy-board.sh`는 단독 실행하면 안 된다.

이 스크립트들은 내부적으로 `deploy-service.sh`를 호출한다.

`deploy-service.sh`는 반드시 `IMAGE_OVERRIDE` 값이 필요하다.

잘못된 예:

```bash
cd /home/um/myApp-Infra
./scripts/deploy-front.sh
```

올바른 예:

```bash
cd /home/um/myApp-Infra
IMAGE_OVERRIDE="myapp-front:some-tag" ./scripts/deploy-front.sh
```

하지만 일반적으로는 각 서비스 저장소의 `scripts/deploy-local.sh`를 사용하는 것이 안전하다.

---

## 10. Front 수동 배포

Ubuntu VM에서 실행한다.

```bash
cd /home/um/myApp-Front
git pull --ff-only origin main
chmod +x scripts/*.sh
./scripts/deploy-local.sh
```

위 스크립트는 다음 작업을 수행한다.

```text
Docker image build
  ↓
myApp-Infra로 이동
  ↓
IMAGE_OVERRIDE 지정
  ↓
./scripts/deploy-front.sh 실행
```

배포 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 11. Member 수동 배포

Ubuntu VM에서 실행한다.

```bash
cd /home/um/myApp-Member
git pull --ff-only origin main
chmod +x mvnw
chmod +x scripts/*.sh
./scripts/deploy-local.sh
```

위 스크립트는 다음 작업을 수행한다.

```text
./mvnw --batch-mode --errors -DskipTests clean package
  ↓
Docker image build
  ↓
myApp-Infra로 이동
  ↓
IMAGE_OVERRIDE 지정
  ↓
./scripts/deploy-member.sh 실행
```

배포 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 12. Board 수동 배포

Ubuntu VM에서 실행한다.

```bash
cd /home/um/myApp-Board
git pull --ff-only origin main
chmod +x mvnw
chmod +x scripts/*.sh
./scripts/deploy-local.sh
```

위 스크립트는 다음 작업을 수행한다.

```text
./mvnw -DskipTests clean package
  ↓
Docker image build
  ↓
myApp-Infra로 이동
  ↓
IMAGE_OVERRIDE 지정
  ↓
./scripts/deploy-board.sh 실행
```

배포 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 13. Nginx 복구

Nginx 컨테이너가 내려갔거나, Nginx를 재생성해야 할 때 사용한다.

먼저 현재 runtime 설정 파일이 있는지 확인한다.

```bash
cd /home/um/myApp-Infra
ls -l nginx/conf.d/default.conf
```

Nginx 설정 문법을 확인한다.

```bash
docker exec myapp-nginx nginx -t
```

Nginx 컨테이너가 죽어 있어서 `docker exec`가 실패하면 다음 복구 스크립트를 실행한다.

```bash
cd /home/um/myApp-Infra
./scripts/start-nginx.sh
```

`start-nginx.sh`는 다음을 확인한다.

```text
Docker 실행 여부
Docker Compose v2 사용 가능 여부
myapp-network 존재 여부
nginx/conf.d/default.conf 존재 여부
현재 active color의 Front 컨테이너 2개 실행 여부
현재 active color의 Member 컨테이너 2개 실행 여부
현재 active color의 Board 컨테이너 2개 실행 여부
Nginx compose config 유효성
Nginx 컨테이너 재생성
Nginx 설정 문법 검사
/, /member/hc, /board/hc 요청 성공 여부
```

복구 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 14. Nginx 설정 파일이 삭제된 경우

`nginx/conf.d/default.conf`가 삭제된 경우 `start-nginx.sh`는 `nginx/templates/default.conf`를 복사해서 기본 설정을 만든다.

주의할 점은 템플릿은 기본적으로 blue 컨테이너를 바라볼 수 있다는 점이다.

따라서 삭제 복구 전에 현재 실제로 살아 있는 컨테이너를 먼저 확인한다.

```bash
docker ps \
  --filter "name=myapp-front-" \
  --filter "name=myapp-member-" \
  --filter "name=myapp-board-" \
  --format "table {{.Names}}\t{{.Status}}"
```

그 다음 복구한다.

```bash
cd /home/um/myApp-Infra
./scripts/start-nginx.sh
```

만약 템플릿이 바라보는 color와 실제 실행 중인 컨테이너 color가 다르면 `start-nginx.sh`가 실패할 수 있다.

이 경우에는 `nginx/conf.d/default.conf`를 실제 실행 중인 컨테이너 color에 맞게 수정한 뒤 다시 실행한다.

확인:

```bash
cd /home/um/myApp-Infra
grep -n "server myapp-" nginx/conf.d/default.conf
```

재실행:

```bash
cd /home/um/myApp-Infra
./scripts/start-nginx.sh
```

---

## 15. Nginx reload

Nginx 설정 문법 검사:

```bash
docker exec myapp-nginx nginx -t
```

Nginx reload:

```bash
docker exec myapp-nginx nginx -s reload
```

Nginx 로그 확인:

```bash
docker logs myapp-nginx --tail 100
```

---

## 16. MariaDB 상태 확인

MariaDB 컨테이너 상태 확인:

```bash
docker ps -a \
  --filter "name=myapp-mariadb" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

MariaDB 로그 확인:

```bash
docker logs myapp-mariadb --tail 100
```

MariaDB 접속:

```bash
docker exec -it myapp-mariadb mariadb -uroot -p
```

접속 후 데이터베이스 확인:

```sql
SHOW DATABASES;
```

Board DB 확인:

```sql
USE myapp_board;
SHOW TABLES;
SELECT * FROM board ORDER BY id DESC LIMIT 10;
```

종료:

```sql
exit
```

---

## 17. Board 데이터 일관성 확인

Board는 Java 메모리 Map이 아니라 MariaDB의 `myapp_board.board` 테이블을 사용해야 한다.

자동 확인은 아래 스크립트에서 수행한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-app-flow.sh
```

정상이라면 아래 항목이 성공한다.

```text
Board container consistency 성공
```

수동으로 확인하려면 현재 실행 중인 Board 컨테이너를 확인한다.

```bash
docker ps \
  --filter "name=myapp-board-" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

각 Board 컨테이너가 같은 게시글 데이터를 보는지 확인한다.

```bash
docker exec myapp-nginx wget -q -T 2 -O - http://myapp-board-green-1:8080/list
docker exec myapp-nginx wget -q -T 2 -O - http://myapp-board-green-2:8080/list
```

현재 active color가 blue라면 green 대신 blue를 사용한다.

```bash
docker exec myapp-nginx wget -q -T 2 -O - http://myapp-board-blue-1:8080/list
docker exec myapp-nginx wget -q -T 2 -O - http://myapp-board-blue-2:8080/list
```

---

## 18. Front 장애 복구

증상:

```text
브라우저에서 화면이 안 뜸
http://127.0.0.1:8080/ 접속 실패
Front 배포 후 빈 화면
Front proxy check 실패
```

확인:

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
```

Front 컨테이너 확인:

```bash
docker ps -a \
  --filter "name=myapp-front-" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

Front 로그 확인:

```bash
docker logs myapp-front-blue-1 --tail 100
docker logs myapp-front-blue-2 --tail 100
docker logs myapp-front-green-1 --tail 100
docker logs myapp-front-green-2 --tail 100
```

현재 active color 확인:

```bash
cd /home/um/myApp-Infra
grep -n "server myapp-front-" nginx/conf.d/default.conf
```

최근 Front 변경이 문제라면 Windows에서 revert 후 push한다.

```bash
cd /c/workspace/myApp-Front
git log --oneline -5
git revert <문제가_된_commit_hash>
git push
```

배포 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 19. Member 장애 복구

증상:

```text
로그인 실패
/member/hc 실패
JWT 관련 오류
로그인 후 글쓰기 시 로그인 화면으로 돌아감
```

확인:

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

Member 컨테이너 확인:

```bash
docker ps -a \
  --filter "name=myapp-member-" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

Member 로그 확인:

```bash
docker logs myapp-member-blue-1 --tail 100
docker logs myapp-member-blue-2 --tail 100
docker logs myapp-member-green-1 --tail 100
docker logs myapp-member-green-2 --tail 100
```

Nginx Member upstream 확인:

```bash
cd /home/um/myApp-Infra
grep -n "server myapp-member-" nginx/conf.d/default.conf
```

최근 Member 변경이 문제라면 Windows에서 revert 후 push한다.

```bash
cd /c/workspace/myApp-Member
git log --oneline -5
git revert <문제가_된_commit_hash>
git push
```

배포 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 20. Board 장애 복구

증상:

```text
게시글 목록 조회 실패
게시글 상세 조회 실패
게시글 등록 실패
게시글 수정 실패
게시글 삭제 실패
Board blue/green 컨테이너 간 데이터 불일치
```

확인:

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

Board 컨테이너 확인:

```bash
docker ps -a \
  --filter "name=myapp-board-" \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

Board 로그 확인:

```bash
docker logs myapp-board-blue-1 --tail 100
docker logs myapp-board-blue-2 --tail 100
docker logs myapp-board-green-1 --tail 100
docker logs myapp-board-green-2 --tail 100
```

Nginx Board upstream 확인:

```bash
cd /home/um/myApp-Infra
grep -n "server myapp-board-" nginx/conf.d/default.conf
```

MariaDB Board 데이터 확인:

```bash
docker exec -it myapp-mariadb mariadb -uroot -p
```

MariaDB 접속 후:

```sql
USE myapp_board;
SHOW TABLES;
SELECT * FROM board ORDER BY id DESC LIMIT 10;
```

최근 Board 변경이 문제라면 Windows에서 revert 후 push한다.

```bash
cd /c/workspace/myApp-Board
git log --oneline -5
git revert <문제가_된_commit_hash>
git push
```

배포 후 검증한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 21. GitHub Actions self-hosted runner 장애 복구

증상:

```text
GitHub Actions가 queued 상태에서 멈춤
self-hosted runner가 offline 상태
workflow가 실행되지 않음
```

runner 프로세스 확인:

```bash
ps -ef | grep -i runner
```

runner 실행 파일 위치 찾기:

```bash
find /home/um -maxdepth 4 -type f -name run.sh
```

예시 위치로 이동:

```bash
cd /home/um/actions-runner
```

수동 runner 방식이면 실행:

```bash
./run.sh
```

서비스 방식이면 상태 확인:

```bash
sudo systemctl status actions.runner* --no-pager
```

서비스 재시작:

```bash
sudo systemctl restart actions.runner*
```

재시작 후 GitHub Actions 화면에서 runner가 online인지 확인한다.

---

## 22. Infra 저장소 검증

Infra 저장소는 GitHub Actions에서 다음 검증을 수행한다.

```text
bash -n scripts/*.sh
docker compose -f compose.yml config --quiet
```

로컬 Ubuntu VM에서 직접 확인하려면 다음 명령어를 실행한다.

```bash
cd /home/um/myApp-Infra
bash -n scripts/*.sh
docker compose -f compose.yml config --quiet
```

전체 운영 검증은 다음 명령어를 실행한다.

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```

---

## 23. 장애 발생 시 판단 순서

장애가 발생하면 아래 순서로 확인한다.

```text
1. Docker가 정상인가?
2. myapp-network가 존재하는가?
3. myapp-nginx가 실행 중인가?
4. nginx/conf.d/default.conf가 존재하는가?
5. Nginx 설정 문법이 정상인가?
6. Nginx upstream이 실제 실행 중인 컨테이너를 바라보는가?
7. active color 컨테이너 2개가 실행 중인가?
8. direct health check가 성공하는가?
9. proxy health check가 성공하는가?
10. MariaDB가 실행 중인가?
11. Board 데이터가 MariaDB에 저장되는가?
12. 최근 배포 commit에서 문제가 생겼는가?
13. GitHub Actions runner가 정상인가?
```

기본 확인 명령어:

```bash
cd /home/um/myApp-Infra
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
docker ps -a --filter "name=myapp-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
docker logs myapp-nginx --tail 100
docker logs myapp-mariadb --tail 100
```

---

## 24. 절대 조심해야 하는 명령어

아래 명령어는 데이터 또는 컨테이너를 삭제할 수 있으므로 신중하게 사용한다.

```bash
docker compose down -v
docker volume rm <volume_name>
docker system prune -a
docker system prune -a --volumes
docker rm -f myapp-mariadb
rm -rf /home/um/myApp-Infra
rm -rf /home/um/myApp-Board
rm -rf /home/um/myApp-Member
rm -rf /home/um/myApp-Front
```

특히 아래 옵션은 MariaDB 데이터 볼륨을 삭제할 수 있다.

```text
-v
--volumes
```

운영 중에는 사용하지 않는다.

---

## 25. 최근 정상 commit

최근 정상 배포 commit은 다음과 같다.

```text
myApp-Infra  : 6a37ab1 Add application flow regression check
myApp-Front  : 6c39580 Run app flow check after front deploy
myApp-Board  : 095fc9a Run app flow check after board deploy
myApp-Member : b0fc77f Run app flow check after member deploy
```

문제가 발생하면 위 commit 이후 변경 사항부터 먼저 확인한다.

각 저장소에서 확인한다.

```bash
git log --oneline -10
```

---

## 26. RUNBOOK 수정 원칙

다음 항목이 바뀌면 이 문서도 함께 수정한다.

```text
컨테이너 이름
서비스 포트
Nginx upstream 구조
배포 스크립트 이름
GitHub Actions workflow 이름
MariaDB 컨테이너 이름
DB 이름
게시글 API 경로
로그인 API 경로
검증 스크립트 항목
```

RUNBOOK 수정 후에는 반드시 검증한다.

```bash
cd /home/um/myApp-Infra
bash -n scripts/*.sh
docker compose -f compose.yml config --quiet
./scripts/check-runtime-state.sh
./scripts/check-app-flow.sh
```