#!/bin/bash

set -e

if [ ! -f "domains.txt" ]; then
    echo "domains.txt not found"
    exit 1
fi

while getopts "46b:" arg; do
    case $arg in
    4)
        DNS_CONFIG=" ipv4=on ipv6=off"
        BIND=""
        ;;
    6)
        DNS_CONFIG=" ipv4=off ipv6=on"
        BIND=""
        ;;
    b)
        DNS_CONFIG=""
        BIND="proxy_bind $OPTARG;"
        ;;
    ?)
        echo "unkonw argument: $arg"
        return 1
        ;;
    esac
done

# 清空
>nginx.conf

cat <<EOF >>nginx.conf
user nginx;
worker_processes auto;
pid /var/run/nginx.pid;
error_log /var/log/nginx/error.log notice;
worker_rlimit_nofile 51200;

events
{
    use epoll;
    worker_connections 51200;
    multi_accept on;
}

stream {
    map \$ssl_preread_server_name \$filtered_sni_name {
EOF

# 打开文件并读取每一行
while IFS= read -r line || [[ -n "$line" ]]; do
    if [ -z "$line" ]; then
        continue
    fi
    if [[ $line == \#* ]]; then
        continue
    fi

    echo "        ~^(.*\.)?${line//./\\.}\$ \$ssl_preread_server_name;" >>nginx.conf
done <"domains.txt"

cat <<EOF >>nginx.conf
        default "127.255.255.255";
    }
EOF

cat <<EOF >>nginx.conf
    resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888]$DNS_CONFIG;
    resolver_timeout 5s;
EOF

cat <<EOF >>nginx.conf
    server {
        listen 443;
        listen [::]:443;
        ssl_preread on;

        proxy_pass \$filtered_sni_name:443;
        $BIND
    }
}

http {
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;

    server {
        listen 80 default_server;
        listen [::]:80 default_server;

        server_name _;

        return 302 https://\$http_host\$request_uri;
    }
}
EOF

mkdir -p conf
mv -f nginx.conf conf/nginx.conf
