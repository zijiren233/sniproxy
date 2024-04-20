#!/bin/bash

set -e

bash ./adguardhome.sh
bash ./nginx.sh $@

# 如果参数中有除 46b:e 之外的参数，则传递给 docker-compose
if [ $# -gt 0 ]; then
    while getopts "46b:e" arg; do
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
