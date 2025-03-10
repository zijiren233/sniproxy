#!/bin/bash

set -ex

RAW_ARGS="$@"

# 如果参数中有除 ed:p:nh: 之外的参数，则传递给 docker-compose
if [ $# -gt 0 ]; then
    while getopts "ed:p:nh:" arg; do
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
    ($DOCKER_COMPOSE exec adguardhome true &&
        ($DOCKER_COMPOSE restart adguardhome)) ||
        ($DOCKER_COMPOSE pull adguardhome &&
            ($DOCKER_COMPOSE down adguardhome || true) &&
            $DOCKER_COMPOSE up -d adguardhome)
    ;;
nginx)
    bash ./nginx.sh $RAW_ARGS
    ($DOCKER_COMPOSE exec nginx true &&
        ($DOCKER_COMPOSE exec nginx nginx -t &&
            $DOCKER_COMPOSE exec nginx nginx -s reload)) ||
        ($DOCKER_COMPOSE pull nginx &&
            ($DOCKER_COMPOSE down nginx || true) &&
            $DOCKER_COMPOSE up -d nginx)
    ;;
"")
    bash ./nginx.sh $RAW_ARGS
    bash ./adguardhome.sh
    ($DOCKER_COMPOSE exec nginx true &&
        ($DOCKER_COMPOSE exec nginx nginx -t &&
            $DOCKER_COMPOSE exec nginx nginx -s reload)) ||
        ($DOCKER_COMPOSE pull nginx &&
            ($DOCKER_COMPOSE down nginx || true) &&
            $DOCKER_COMPOSE up -d nginx)
    ($DOCKER_COMPOSE exec adguardhome true &&
        ($DOCKER_COMPOSE restart adguardhome)) ||
        ($DOCKER_COMPOSE pull adguardhome &&
            ($DOCKER_COMPOSE down adguardhome || true) &&
            $DOCKER_COMPOSE up -d adguardhome)
    ;;
*)
    echo "Invalid argument: $MORE_ARGS"
    ;;
esac
$DOCKER_COMPOSE logs -f
