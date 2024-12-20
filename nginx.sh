#!/bin/bash

set -e

if [ -z "$DOMAINS_FILE" ]; then
    DOMAINS_FILE="domains.txt"
fi
if [ ! -f "$DOMAINS_FILE" ]; then
    echo "nginx: $DOMAINS_FILE not found"
    exit 1
fi
if [ -z "$CONFIG_DIR" ]; then
    CONFIG_DIR="./conf"
fi
mkdir -p $CONFIG_DIR

while getopts "46b:ed:p:" arg; do
    case $arg in
    4)
        DNS_CONFIG="ipv4=on ipv6=off"
        ;;
    6)
        DNS_CONFIG="ipv4=off ipv6=on"
        ;;
    b)
        DNS_CONFIG=""
        BIND="proxy_bind $OPTARG;"
        ;;
    e)
        ERROR_LOG="error_log /var/log/nginx/error.log notice;"
        ;;
    d)
        DNS="$OPTARG"
        ;;
    p)
        LISTEN_PORTS="$LISTEN_PORTS,$OPTARG"
        ;;
    ?)
        echo "unkonw argument: $arg"
        return 1
        ;;
    esac
done

# 展开端口范围
function expand_port_range() {
    local ports=$1
    local expanded=""

    # 按逗号分割
    IFS=',' read -ra PORT_RANGES <<<"$ports"

    for range in "${PORT_RANGES[@]}"; do
        # 去除空格
        range=$(echo "$range" | xargs)
        if [[ $range =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # 是端口范围
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if [ "$start" -gt "$end" ]; then
                echo "Invalid port range: $range" >&2
                exit 1
            fi
            for ((port = start; port <= end; port++)); do
                if [ -z "$expanded" ]; then
                    expanded="$port"
                else
                    expanded="$expanded,$port"
                fi
            done
        else
            # 单个端口
            if [ -z "$expanded" ]; then
                expanded="$range"
            else
                expanded="$expanded,$range"
            fi
        fi
    done

    # 去重
    echo "$expanded" | tr ',' '\n' | sort -nu | tr '\n' ',' | sed 's/,$//'
}

LISTEN_PORTS=$(echo $LISTEN_PORTS | xargs)
if [ -z "$LISTEN_PORTS" ]; then
    LISTEN_PORTS="443"
fi
LISTEN_PORTS=$(expand_port_range "$LISTEN_PORTS")

if [ -z "$DNS" ]; then
    DNS="1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888]"
fi
if [[ $DNS != *"valid="* ]]; then
    DNS="$DNS valid=15s"
fi

if [ -z "$ERROR_LOG" ]; then
    ERROR_LOG="error_log off;"
fi

if [ -z "$WORKER_CONNECTIONS" ]; then
    WORKER_CONNECTIONS="65535"
fi

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

pools=()

function AddPool() {
    local e
    local field="$2"
    for e in "${pools[@]}"; do
        if [[ "$e" == "$1@"* ]]; then
            return 0
        fi
    done
    pools+=("$1@$field")
}

# 把.替换成_,把:替换成-
function NewPoolName() {
    local POOL_NAME=${1//./_}
    echo ${POOL_NAME//:/-}
}

function BuildPools() {
    for key in "${pools[@]}"; do
        local server="${key%@*}"
        local fields="${key#*@}"
        echo "    upstream $(NewPoolName ${server}) {"
        echo "        random two least_conn;"
        # 按照,或;分割field并循环
        IFS=',;'
        for server_addr in $fields; do
            # trim空格
            server_addr=$(echo "$server_addr" | xargs)
            # 获取第一个空格之前的地址
            local addr=$(echo "$server_addr" | awk '{print $1}')

            # 处理端口范围
            if [[ $addr =~ ^(.*):([0-9]+-[0-9]+)$ ]]; then
                local host="${BASH_REMATCH[1]}"
                local port_range="${BASH_REMATCH[2]}"
                local expanded_ports=$(expand_port_range "$port_range")
                IFS=',' read -ra PORTS <<<"$expanded_ports"
                for port in "${PORTS[@]}"; do
                    echo "        server ${host}:${port}${server_addr#$addr};"
                done
            else
                # 如果地址没有端口号，则添加默认端口443
                if [[ $addr != *:* ]]; then
                    server_addr="${addr}:443${server_addr#$addr}"
                fi
                echo "        server ${server_addr};"
            fi
        done
        echo "    }"
    done
    unset IFS
}

HOSTS_DEFAULT=""
HOSTS_IPv4=""
HOSTS_IPv6=""
HOSTS_IPv4_BIND=""
HOSTS_IPv6_BIND=""
ALLOW=""
EXTRA_STREAM_SERVERS=""
DEFAULT_SOURCE=""

while IFS= read -r line || [ -n "$line" ]; do
    # trim
    line=$(echo "$line" | xargs)
    # 如果是空行则清空IP版本和速率限制以及默认SOURCE
    if [ -z "$line" ]; then
        IP_VERSION=""
        RATE=""
        DEFAULT_SOURCE=""
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
        IP_VERSION="${line#!}"
        continue
    fi
    # 如果是<开头则设置速录限制
    if [[ $line == \<* ]]; then
        RATE="${line#<}"
        continue
    fi
    # 如果是@开头则设置默认SOURCE
    if [[ $line == @* ]]; then
        DEFAULT_SOURCE="${line#@}"
        continue
    fi
    # 如果是&开头则设置允许的IP
    if [[ $line == \&* ]]; then
        # 去掉&并trim
        IPS="${line#&}"
        IPS=$(echo $IPS | xargs)
        # 按照,分割IP并添加到ALLOW中
        for IP in $(echo $IPS | sed "s/,/ /g"); do
            IP=$(echo $IP | xargs)
            if [ -z "$IP" ]; then
                continue
            fi
            if [ "$ALLOW" == "" ]; then
                ALLOW="allow $IP;"
            else
                ALLOW="$ALLOW\n    allow $IP;"
            fi
        done
        continue
    fi
    # 解析 ``` 开头多行代码块
    if [[ $line == "\`\`\`"* ]]; then
        content=""
        while IFS= read -r command_line; do
            if [[ $(echo "$command_line" | xargs) == "\`\`\`" ]]; then
                break
            fi
            if [ -n "$content" ]; then
                content=$(echo -e "$content\n    $command_line")
            else
                content="$command_line"
            fi
        done
        if [ -n "$content" ]; then
            if [ -n "$EXTRA_STREAM_SERVERS" ]; then
                EXTRA_STREAM_SERVERS=$(echo -e "$EXTRA_STREAM_SERVERS\n\n    $content")
            else
                EXTRA_STREAM_SERVERS="$content"
            fi
        fi
        continue
    fi
    # 如果是单行注释块 ` 结尾
    if [[ $line == *"\`" ]]; then
        # 提取`和`之间的内容
        content=$(echo "$line" | sed 's/\`\(.*\)\`/\1/' | xargs)
        if [ -n "$content" ]; then
            if [ -n "$EXTRA_STREAM_SERVERS" ]; then
                EXTRA_STREAM_SERVERS=$(echo -e "$EXTRA_STREAM_SERVERS\n\n    $content")
            else
                EXTRA_STREAM_SERVERS="$content"
            fi
        fi
        continue
    fi

    # 把DOMAIN按照@分割，第一个为域名，第二个为SOURCE，且需要trim
    DOMAIN=$(echo $line | awk -F@ '{print $1}' | xargs)
    SOURCE=$(echo $line | awk -F@ '{print $2}' | xargs)

    # 检查是否以=开头，如果是则不添加.前缀
    if [[ $DOMAIN == =* ]]; then
        DOMAIN="${DOMAIN#=}"
        PREFIX=""
    else
        PREFIX="."
    fi

    # 如果SOURCE为空且DEFAULT_SOURCE不为空，则使用DEFAULT_SOURCE
    if [ -z "$SOURCE" ] && [ -n "$DEFAULT_SOURCE" ]; then
        SOURCE="$DEFAULT_SOURCE"
    fi

    if [ "$SOURCE" != "" ]; then
        AddPool "$DOMAIN" "$SOURCE"
        SOURCES=$(echo -e "$SOURCES\n        $PREFIX$DOMAIN $(NewPoolName $DOMAIN);")
    fi

    DOMAIN="$PREFIX${DOMAIN}"

    # 如果速录限制不为空，则添加到RATES变量中
    if [ "$RATE" != "" ]; then
        RATES=$(echo -e "$RATES\n        $DOMAIN $RATE;")
    fi

    case $IP_VERSION in
    "ipv4")
        if [ "$HOSTS_IPv4" == "" ]; then
            HOSTS_IPv4=""
        fi
        HOSTS_IPv4="$HOSTS_IPv4 $DOMAIN"
        ;;
    "ipv6")
        if [ "$HOSTS_IPv6" == "" ]; then
            HOSTS_IPv6=""
        fi
        HOSTS_IPv6="$HOSTS_IPv6 $DOMAIN"
        ;;
    "")
        if [ "$HOSTS_DEFAULT" == "" ]; then
            HOSTS_DEFAULT=""
        fi
        HOSTS_DEFAULT="$HOSTS_DEFAULT $DOMAIN"
        ;;
    *)
        BINDS=$(echo -e "$BINDS\n        $DOMAIN $IP_VERSION;")
        if [ $(IsIPv4 $IP_VERSION) -eq 0 ]; then
            if [ "$HOSTS_IPv4_BIND" == "" ]; then
                HOSTS_IPv4_BIND=""
            fi
            HOSTS_IPv4_BIND="$HOSTS_IPv4_BIND $DOMAIN"
        elif [ $(IsIPv6 $IP_VERSION) -eq 0 ]; then
            if [ "$HOSTS_IPv6_BIND" == "" ]; then
                HOSTS_IPv6_BIND=""
            fi
            HOSTS_IPv6_BIND="$HOSTS_IPv6_BIND $DOMAIN"
        else
            echo "nginx: unknown IP version: $IP_VERSION, only ipv4 or ipv6 are supported"
            exit 1
        fi
        ;;
    esac
done <"$DOMAINS_FILE"

if [ -n "$ALLOW" ]; then
    ALLOW=$(echo -e "$ALLOW\n    deny all;")
fi

LISTEN_CONFIG=""
REUSEPORT_CONFIG=""
for port in $(echo $LISTEN_PORTS | tr ',' ' '); do
    port=$(echo $port | xargs)
    if [ -z "$port" ]; then
        continue
    fi
    if [ -z "$LISTEN_CONFIG" ]; then
        LISTEN_CONFIG="$(echo -e "listen $port;\n        listen [::]:$port;")"
    else
        LISTEN_CONFIG="$(echo -e "$LISTEN_CONFIG\n        listen $port;\n        listen [::]:$port;")"
    fi
    if [ -z "$REUSEPORT_CONFIG" ]; then
        REUSEPORT_CONFIG="$(echo -e "listen $port reuseport so_keepalive=60s:20s:3;\n        listen [::]:$port reuseport so_keepalive=60s:20s:3;")"
    else
        REUSEPORT_CONFIG="$(echo -e "$REUSEPORT_CONFIG\n        listen $port reuseport so_keepalive=60s:20s:3;\n        listen [::]:$port reuseport so_keepalive=60s:20s:3;")"
    fi
done

if [ "$HOSTS_DEFAULT" != "" ]; then
    DEFAULT_SERVER="server {
        $LISTEN_CONFIG
        server_name$HOSTS_DEFAULT;
        ssl_preread on;

        proxy_pass \$source;
        $BIND
    }"
fi

if [ "$HOSTS_IPv4" != "" ]; then
    IPv4_SERVER="server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv4;
        ssl_preread on;
        resolver $DNS ipv4=on ipv6=off;

        proxy_pass \$source;
    }"
fi

if [ "$HOSTS_IPv4_BIND" != "" ]; then
    IPv4_BIND_SERVER="server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv4_BIND;
        ssl_preread on;
        resolver $DNS ipv4=on ipv6=off;

        proxy_pass \$source;
        proxy_bind \$bind;
    }"
fi

if [ "$HOSTS_IPv6" != "" ]; then
    IPv6_SERVER="server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv6;
        ssl_preread on;
        resolver $DNS ipv4=off ipv6=on;

        proxy_pass \$source;
    }"
fi

if [ "$HOSTS_IPv6_BIND" != "" ]; then
    IPv6_BIND_SERVER="server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv6_BIND;
        ssl_preread on;
        resolver $DNS ipv4=off ipv6=on;

        proxy_pass \$source;
        proxy_bind \$bind;
    }"
fi

readonly tmp_file=$(mktemp)

cat <<EOF >$tmp_file
user nginx;
worker_processes auto;
pid /var/run/nginx.pid;
$ERROR_LOG
worker_rlimit_nofile 65535;

events
{
    use epoll;
    # maybe oom
    worker_connections $WORKER_CONNECTIONS;
    multi_accept on;
}

stream {
    log_format basic '[\$time_local] \$remote_addr:\$remote_port → \$ssl_preread_server_name | \$upstream_addr | ↑ \$upstream_bytes_sent | ↓ \$upstream_bytes_received | \$session_time s | \$status';
    map \$status \$loggable {
        default 1;
    }
    access_log /var/log/nginx/access.log basic if=\$loggable;
    resolver $DNS $DNS_CONFIG;

    $ALLOW

$(BuildPools)
    map \$ssl_preread_server_name \$source {
        hostnames;$SOURCES
        default \$ssl_preread_server_name:443;
    }
    map \$ssl_preread_server_name \$bind {
        hostnames;$BINDS
        default 0;
    }
    map \$ssl_preread_server_name \$rate {
        hostnames;$RATES
        default 0;
    }
    proxy_connect_timeout 10s;
    proxy_timeout 90s;
    proxy_buffer_size 32k;
    tcp_nodelay on;
    preread_timeout 10s;
    resolver_timeout 10s;
    proxy_socket_keepalive on;
    proxy_half_close on;
    proxy_upload_rate \$rate;
    proxy_download_rate \$rate;
    $DEFAULT_SERVER
    $IPv4_SERVER
    $IPv4_BIND_SERVER
    $IPv6_SERVER
    $IPv6_BIND_SERVER
    server {
        $REUSEPORT_CONFIG
        server_name ~^.*$;
        ssl_preread on;

        access_log off;

        deny all;
        return 0;
    }

    $EXTRA_STREAM_SERVERS
}

http {
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    access_log off;
    error_log off;

    $ALLOW

    server {
        listen 80 default_server reuseport;
        listen [::]:80 default_server reuseport;
        server_name _;

        return 302 https://\$http_host\$request_uri;
    }
}
EOF

mv -f $tmp_file $CONFIG_DIR/nginx.conf
