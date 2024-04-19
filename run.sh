#!/bin/bash

set -e

bash ./adguardhome.sh
bash ./nginx.sh

if ! command -v docker-compose &>/dev/null; then
    if ! command -v docker &>/dev/null; then
        echo "docker not found"
        exit 1
    fi
    docker compose up -d
    docker compose logs -f
else
    docker-compose up -d
    docker-compose logs -f
fi
