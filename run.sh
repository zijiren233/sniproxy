#!/bin/bash

set -ex

RAW_ARGS="$@"

# 写入 .env 文件
cat > .env <<EOF
NGINX_ARGS=$RAW_ARGS
EOF

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
	($DOCKER_COMPOSE exec nginx true &&
		($DOCKER_COMPOSE exec nginx nginx -t &&
			$DOCKER_COMPOSE exec nginx nginx -s reload)) ||
		($DOCKER_COMPOSE pull nginx &&
			($DOCKER_COMPOSE down nginx || true) &&
			$DOCKER_COMPOSE up -d nginx)
	;;
"")
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
