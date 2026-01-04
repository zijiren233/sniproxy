#!/bin/bash

set -ex

if ! command -v docker &>/dev/null; then
    echo "docker not found"
    exit 1
fi

if docker compose version &>/dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    if command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        echo "Neither docker compose nor docker-compose found"
        exit 1
    fi
fi

bash ./adguardhome.sh

($DOCKER_COMPOSE exec adguardhome true &&
    ($DOCKER_COMPOSE restart adguardhome)) ||
    ($DOCKER_COMPOSE pull adguardhome &&
        ($DOCKER_COMPOSE down adguardhome || true) &&
        $DOCKER_COMPOSE up -d adguardhome)

$DOCKER_COMPOSE logs -f adguardhome
