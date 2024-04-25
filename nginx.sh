#!/bin/bash

set -e

if [ ! -f "domains.txt" ]; then
    echo "domains.txt not found"
    exit 1
fi

ERROR_LOG="error_log off;"
HOSTS_DEFAULT=""
HOSTS_IPv4=""
HOSTS_IPv6=""
HOSTS_IPv4_BIND=""
HOSTS_IPv6_BIND=""

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

function IsIPv4() {
    local IP=$1
    if [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "0"
    else
        echo "1"
    fi
}

function IsIPv6() {
    if [[ "$1" =~ ^[0-9a-fA-F:]+$ ]]; then
        echo "0"
    else
        echo "1"
    fi
}

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
        if [ "$HOSTS_IPv4" == "" ]; then
            HOSTS_IPv4=""
        fi
        HOSTS_IPv4="$HOSTS_IPv4 .$line"
        ;;
    "ipv6")
        if [ "$HOSTS_IPv6" == "" ]; then
            HOSTS_IPv6=""
        fi
        HOSTS_IPv6="$HOSTS_IPv6 .$line"
        ;;
    "")
        if [ "$HOSTS_DEFAULT" == "" ]; then
            HOSTS_DEFAULT=""
        fi
        HOSTS_DEFAULT="$HOSTS_DEFAULT .$line"
        ;;
    *)
        BINDS=$(echo -e "$BINDS\n        .$line $IP_VERSION;")
        if [ $(IsIPv4 $IP_VERSION) -eq 0 ]; then
            if [ "$HOSTS_IPv4_BIND" == "" ]; then
                HOSTS_IPv4_BIND=""
            fi
            HOSTS_IPv4_BIND="$HOSTS_IPv4_BIND .$line"
        elif [ $(IsIPv6 $IP_VERSION) -eq 0 ]; then
            if [ "$HOSTS_IPv6_BIND" == "" ]; then
                HOSTS_IPv6_BIND=""
            fi
            HOSTS_IPv6_BIND="$HOSTS_IPv6_BIND .$line"
        else
            echo "unknown IP version: $IP_VERSION, only ipv4 or ipv6 are supported"
            exit 1
        fi
        ;;
    esac
done <"domains.txt"

if [ "$HOSTS_DEFAULT" != "" ]; then
    DEFAULT_SERVER="server {
        listen 443;
        listen [::]:443;
        server_name$HOSTS_DEFAULT;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888]$DNS_CONFIG;

        proxy_pass \$ssl_preread_server_name:443;
        $BIND
    }"
fi

if [ "$HOSTS_IPv4" != "" ]; then
    IPv4_SERVER="server {
        listen 443;
        listen [::]:443;
        server_name$HOSTS_IPv4;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=on ipv6=off;

        proxy_pass \$ssl_preread_server_name:443;
    }"
fi

if [ "$HOSTS_IPv4_BIND" != "" ]; then
    IPv4_BIND_SERVER="server {
        listen 443;
        listen [::]:443;
        server_name$HOSTS_IPv4_BIND;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=on ipv6=off;

        proxy_pass \$ssl_preread_server_name:443;
        proxy_bind \$bind;
    }"
fi

if [ "$HOSTS_IPv6" != "" ]; then
    IPv6_SERVER="server {
        listen 443;
        listen [::]:443;
        server_name$HOSTS_IPv6;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=off ipv6=on;

        proxy_pass \$ssl_preread_server_name:443;
    }"
fi

if [ "$HOSTS_IPv6_BIND" != "" ]; then
    IPv6_BIND_SERVER="server {
        listen 443;
        listen [::]:443;
        server_name$HOSTS_IPv6_BIND;
        resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=off ipv6=on;

        proxy_pass \$ssl_preread_server_name:443;
        proxy_bind \$bind;
    }"
fi

cat <<EOF >nginx.conf
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
    log_format basic '[\$time_local] \$remote_addr:\$remote_port → \$ssl_preread_server_name | \$upstream_addr | ↑ \$upstream_bytes_sent | ↓ \$upstream_bytes_received | \$session_time s | \$status';
    map \$status \$loggable {
        default 1;
    }
    access_log /var/log/nginx/access.log basic if=\$loggable;
    map \$hostname \$bind {
        hostnames;$BINDS
        default 0;
    }
    proxy_connect_timeout 10s;
    proxy_timeout 90s;
    proxy_buffer_size 24k;
    tcp_nodelay on;
    ssl_preread on;
    preread_timeout 5s;
    resolver_timeout 5s;
    $DEFAULT_SERVER
    $IPv4_SERVER
    $IPv4_BIND_SERVER
    $IPv6_SERVER
    $IPv6_BIND_SERVER
    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        server_name ~^.*$;

        access_log off;

        deny all;
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

        return 302 https://\$http_host\$request_uri;
    }
}
EOF

mkdir -p conf
mv -f nginx.conf conf/nginx.conf
