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

    cat /tmp/front-color
    cat /tmp/member-color
    cat /tmp/board-color

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
