#!/bin/bash

set -e

RAW_ARGS="$@"

# 如果参数中有除 46b:ed:p: 之外的参数，则传递给 docker-compose
if [ $# -gt 0 ]; then
    while getopts "46b:ed:p:" arg; do
        case $arg in
        ?) ;;
        esac
    done
    shift $((OPTIND - 1))
    MORE_ARGS="$@"
fi

if ! command -v docker-compose &>/dev/null; then
    if ! command -v docker &>/dev/null; then
        echo "docker not found"
        exit 1
    fi
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

case "$MORE_ARGS" in
adguardhome)
    bash ./adguardhome.sh
    ($DOCKER_COMPOSE exec adguardhome true && $DOCKER_COMPOSE restart adguardhome) ||
        ($DOCKER_COMPOSE pull adguardhome && $DOCKER_COMPOSE down adguardhome && $DOCKER_COMPOSE up adguardhome -d)
    ;;
nginx)
    bash ./nginx.sh $RAW_ARGS
    ($DOCKER_COMPOSE exec nginx nginx -t && $DOCKER_COMPOSE exec nginx nginx -s reload) ||
        ($DOCKER_COMPOSE exec nginx nginx true && $DOCKER_COMPOSE restart nginx) ||
        ($DOCKER_COMPOSE pull nginx && $DOCKER_COMPOSE down nginx && $DOCKER_COMPOSE up nginx -d)
    ;;
"")
    bash ./nginx.sh $RAW_ARGS
    bash ./adguardhome.sh
    ($DOCKER_COMPOSE exec nginx nginx -t && $DOCKER_COMPOSE exec nginx nginx -s reload) ||
        ($DOCKER_COMPOSE exec nginx nginx true && $DOCKER_COMPOSE restart nginx) ||
        ($DOCKER_COMPOSE pull nginx && $DOCKER_COMPOSE down nginx && $DOCKER_COMPOSE up nginx -d)
    ($DOCKER_COMPOSE exec adguardhome true && $DOCKER_COMPOSE restart adguardhome) ||
        ($DOCKER_COMPOSE pull adguardhome && $DOCKER_COMPOSE down adguardhome && $DOCKER_COMPOSE up adguardhome -d)
    ;;
*)
    echo "Invalid argument: $MORE_ARGS"
    ;;
esac
$DOCKER_COMPOSE logs -f
