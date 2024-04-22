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
        ;;
    6)
        DNS_CONFIG=" ipv4=off ipv6=on"
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
    log_format basic '[\$time_local] \$proxy_protocol_addr:\$proxy_protocol_port → \$ssl_preread_server_name | \$upstream_addr | ↑ \$upstream_bytes_sent | ↓ \$upstream_bytes_received | \$session_time s | \$status';
    map \$status \$loggable {
        default 1;
    }
    access_log /var/log/nginx/access.log basic if=\$loggable;
    tcp_nodelay on;

    map \$ssl_preread_server_name \$filtered_sni_name {
        hostnames;
EOF

# 打开文件并读取每一行
while IFS= read -r line || [[ -n "$line" ]]; do
    # 如果是空行则清空IP版本
    if [ -z "$line" ]; then
        IP_VERSION=""
        continue
    fi
    # 如果是注释行则跳过
    if [[ $line == //* ]]; then
        continue
    fi
    # 跳过adguardhome规则
    if [[ $line == \#* ]]; then
        continue
    fi
    # 如果是!开头，则设置使用的IP版本
    if [[ $line == \!* ]]; then
        IP_VERSION=${line#!}
        continue
    fi

    case $IP_VERSION in
    "ipv4")
        echo "        .$line unix:/var/run/ipv4.sock;" >>nginx.conf
        ;;
    "ipv6")
        echo "        .$line unix:/var/run/ipv6.sock;" >>nginx.conf
        ;;
    "")
        echo "        .$line unix:/var/run/default.sock;" >>nginx.conf
        ;;
    *)
        echo "unknown IP version: $IP_VERSIO, only ipv4 or ipv6 are supported"
        exit 1
        ;;
    esac
done <"domains.txt"

cat <<EOF >>nginx.conf
        default "";
    }
EOF

cat <<EOF >>nginx.conf
    resolver_timeout 5s;
EOF

cat <<EOF >>nginx.conf
    proxy_connect_timeout 10s;
    proxy_timeout 90s;
    preread_timeout 10s;
    proxy_buffer_size 24k;
    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        ssl_preread on;

        access_log off;

        proxy_pass \$filtered_sni_name;
        proxy_protocol on;
    }
    server {
        listen unix:/var/run/default.sock proxy_protocol;
        ssl_preread on;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888]$DNS_CONFIG;

        proxy_pass \$ssl_preread_server_name:443;
        $BIND
    }
    server {
        listen unix:/var/run/ipv4.sock proxy_protocol;
        ssl_preread on;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=on ipv6=off;

        proxy_pass \$ssl_preread_server_name:443;
    }
    server {
        listen unix:/var/run/ipv6.sock proxy_protocol;
        ssl_preread on;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=off ipv6=on;

        proxy_pass \$ssl_preread_server_name:443;
    }
}

http {
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    access_log off;
    error_log off;

    server {
        listen 80 default_server reuseport;
        listen [::]:80 default_server reuseport;

        server_name _;

        proxy_buffers off;

        return 302 https://\$http_host\$request_uri;
    }
}
EOF

mkdir -p conf
mv -f nginx.conf conf/nginx.conf
