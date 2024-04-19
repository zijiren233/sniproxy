#!/bin/bash

set -e

if [ ! -f "domains.txt" ]; then
    echo "domains.txt not found"
    exit 1
fi

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
while IFS= read -r line; do
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

    resolver 1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888] ipv4=off;

    server {
        listen 443;
        listen [::]:443;
        ssl_preread on;

        proxy_pass \$filtered_sni_name:443;
        # proxy_bind <ip>;
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
