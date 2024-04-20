#!/bin/bash

set -e

bash ./adguardhome.sh
bash ./nginx.sh $@

getopts "46b:" opt
shift $((OPTIND - 1))
MORE_ARGS="$@"

if ! command -v docker-compose &>/dev/null; then
    if ! command -v docker &>/dev/null; then
        echo "docker not found"
        exit 1
    fi
    docker compose pull $MORE_ARGS
    docker compose down $MORE_ARGS
    docker compose up $MORE_ARGS -d
    docker compose logs -f
else
    docker compose pull $MORE_ARGS
    docker-compose down $MORE_ARGS
    docker-compose up $MORE_ARGS -d
    docker-compose logs -f
fi
