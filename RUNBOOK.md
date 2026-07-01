# myApp Infra Runbook

## Current Blue/Green Deployment Commands

Current verified runtime state:

- Front: green
- Member: blue
- Board: blue

Main access URL from Windows browser:

    http://127.0.0.1:8080

## Deploy Front

    cd /home/um/myApp-Infra
    ./scripts/deploy-front.sh

## Deploy Member

    cd /home/um/myApp-Infra
    ./scripts/deploy-member.sh

## Deploy Board

    cd /home/um/myApp-Infra
    ./scripts/deploy-board.sh

## Check Current Active Colors

    cat /home/um/myApp-Infra/runtime/front-color
    cat /home/um/myApp-Infra/runtime/member-color
    cat /home/um/myApp-Infra/runtime/board-color

## Check Runtime Containers

    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

## Check Nginx Config

    docker exec myapp-nginx nginx -t
    docker exec myapp-nginx grep -n "server myapp-" /etc/nginx/conf.d/default.conf

## Current Important Scripts

    /home/um/myApp-Infra/scripts/deploy-front.sh
    /home/um/myApp-Infra/scripts/deploy-member.sh
    /home/um/myApp-Infra/scripts/deploy-board.sh
    /home/um/myApp-Infra/scripts/rollback-front.sh
    /home/um/myApp-Infra/scripts/rollback-member.sh
    /home/um/myApp-Infra/scripts/rollback-board.sh
    /home/um/myApp-Infra/scripts/replace-nginx-upstream.sh

## Notes

replace-nginx-upstream.sh updates only one upstream block at a time.

This prevents Front, Member, and Board deployments from overwriting each other's Nginx upstream settings.

If nginx -t fails during upstream replacement, the script restores the previous Nginx config backup.


## GitHub Actions Manual Deploy

Each service repository has a manual GitHub Actions workflow.

### Front

Repository:

    https://github.com/tripthelight/myApp-Front

Workflow:

    Deploy Front Local

GitHub path:

    myApp-Front -> Actions -> Deploy Front Local -> Run workflow

This workflow runs:

    cd /home/um/myApp-Infra
    ./scripts/deploy-front.sh

### Member

Repository:

    https://github.com/tripthelight/myApp-Member

Workflow:

    Deploy Member Local

GitHub path:

    myApp-Member -> Actions -> Deploy Member Local -> Run workflow

This workflow runs:

    cd /home/um/myApp-Infra
    ./scripts/deploy-member.sh

### Board

Repository:

    https://github.com/tripthelight/myApp-Board

Workflow:

    Deploy Board Local

GitHub path:

    myApp-Board -> Actions -> Deploy Board Local -> Run workflow

This workflow runs:

    cd /home/um/myApp-Infra
    ./scripts/deploy-board.sh

## Verified Actions Result

Front manual deployment was verified successfully.

Verified flow:

    GitHub Run workflow
    -> Ubuntu self-hosted runner
    -> /home/um/myApp-Infra/scripts/deploy-front.sh
    -> Nginx upstream switch
    -> old Front containers removed

Verified runtime state after Actions deploy:

    Front: blue
    Member: blue
    Board: blue

Verified Nginx upstream:

    server myapp-front-blue-1:80;
    server myapp-front-blue-2:80;
    server myapp-member-blue-1:8080;
    server myapp-member-blue-2:8080;
    server myapp-board-blue-1:8080;
    server myapp-board-blue-2:8080;
