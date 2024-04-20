#!/bin/bash

set -e

if [ ! -f "domains.txt" ]; then
    echo "domains.txt not found"
    exit 1
fi

ERROR_LOG="error_log off;"

while getopts "46b:e" arg; do
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
    e)
        ERROR_LOG="error_log /var/log/nginx/error.log notice;"
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
$ERROR_LOG
worker_rlimit_nofile 51200;

events
{
    use epoll;
    worker_connections 51200;
    multi_accept on;
}

stream {
    log_format basic '[\$time_local] \$remote_addr → \$ssl_preread_server_name | \$upstream_addr ↑ \$upstream_bytes_sent ↓ \$upstream_bytes_received \$upstream_connect_time';
    access_log /var/log/nginx/access.log basic;

    map \$ssl_preread_server_name \$filtered_sni_name {
EOF

# 打开文件并读取每一行
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $line == //* ]]; then
        continue
    fi
    if [ -z "$line" ]; then
        continue
    fi
    if [[ $line == \#* ]]; then
        continue
    fi

    echo "        ~^(.*\.)?${line//./\\.}\$ \$ssl_preread_server_name;" >>nginx.conf
done <"domains.txt"

cat <<EOF >>nginx.conf
        default "";
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

        proxy_buffer_size 24k;
        proxy_connect_timeout 30s;
        proxy_timeout 90s;
    }
}

http {
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    access_log off;
    error_log off;

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
