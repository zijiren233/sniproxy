#!/bin/bash

set -ex

RAW_ARGS="$@"

# 写入 .env 文件
cat > .env <<EOF
NGINX_ARGS=$RAW_ARGS
EOF

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

($DOCKER_COMPOSE exec nginx true &&
    ($DOCKER_COMPOSE exec nginx nginx -t &&
        $DOCKER_COMPOSE exec nginx nginx -s reload)) ||
    ($DOCKER_COMPOSE pull nginx &&
        ($DOCKER_COMPOSE down nginx || true) &&
        $DOCKER_COMPOSE up -d nginx)

$DOCKER_COMPOSE logs -f nginx
