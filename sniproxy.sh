#!/bin/bash

set -e

if [ ! -f "domains.txt" ]; then
    echo "domains.txt not found"
    exit 1
fi

# 清空
>sniproxy.conf

cat <<EOF >>sniproxy.conf
user daemon
pidfile /var/tmp/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

resolver {
    nameserver 8.8.8.8
    nameserver 1.1.1.1
    mode ipv4_first
}

listener 0.0.0.0:80 {
    proto http
    table whitelist
    access_log {
        filename /var/log/sniproxy/http_access.log
        priority notice
    }
}

listener 0.0.0.0:443 {
    proto tls
    table whitelist
    access_log {
        filename /var/log/sniproxy/https_access.log
        priority notice
    }
}

table whitelist {
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
    if [[ $line == \!* ]]; then
        continue
    fi
    if [[ $line == \<* ]]; then
        continue
    fi
    # 把line按照@分割，第一个为域名，不需要后面的，且需要trim
    DOMAIN=$(echo $line | awk -F@ '{print $1}' | xargs)
    echo "    .*${DOMAIN//./\\.}\$ *" >>sniproxy.conf
done <"domains.txt"

cat <<EOF >>sniproxy.conf
}
EOF

mkdir -p conf
mv -f sniproxy.conf conf/sniproxy.conf
