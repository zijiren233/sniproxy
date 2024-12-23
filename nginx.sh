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

while getopts "ed:p:nh:" arg; do
    case $arg in
    d)
        DNS="$OPTARG"
        ;;
    e)
        ERROR_LOG="error_log /var/log/nginx/error.log notice;"
        FORBIDDEN_LOG="1"
        ;;
    p)
        LISTEN_PORTS="$LISTEN_PORTS,$OPTARG"
        ;;
    n)
        DISABLE_HTTP=1
        ;;
    h)
        HTTP_PORTS="$OPTARG"
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

if [ -z "$DNS" ]; then
    DNS="1.1.1.1 8.8.8.8 [2606:4700:4700::1111] [2001:4860:4860::8888]"
fi
if [[ $DNS != *"valid="* ]]; then
    DNS="$DNS valid=15s"
fi

if [ -z "$ERROR_LOG" ]; then
    ERROR_LOG="error_log /dev/null;"
fi

if [ -z "$FORBIDDEN_LOG" ]; then
    FORBIDDEN_LOG="0"
fi

if [ -z "$WORKER_CONNECTIONS" ]; then
    WORKER_CONNECTIONS="65535"
fi

if [ -z "$HTTP_PORTS" ]; then
    HTTP_PORTS="80"
fi

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
HOSTS_IPv4_BIND=""
HOSTS_IPv6=""
HOSTS_IPv6_BIND=""
ALLOW=""
EXTRA_STREAM_SERVERS=""
DEFAULT_SOURCE=""
GLOBAL_IP_VERSION=""
GLOBAL_RATE=""
GLOBAL_SOURCE=""
HTTP_SERVER=""

# 存储已使用的bind组合
used_bind_groups=""

# 检查IP版本是否一致
function check_ip_version() {
    local ips="$1"
    local is_ipv4=0
    local is_ipv6=0
    
    IFS=',' read -ra IP_LIST <<<"$ips"
    for ip in "${IP_LIST[@]}"; do
        ip=$(echo "$ip" | xargs)
        if [[ $ip =~ ^\[.*\]$ ]] || [[ $ip =~ : ]]; then
            is_ipv6=1
        else
            is_ipv4=1
        fi
    done
    
    if [ $is_ipv4 -eq 1 ] && [ $is_ipv6 -eq 1 ]; then
        echo "Error: Mixed IP versions in bind group: $ips" >&2
        exit 1
    fi
    
    if [ $is_ipv6 -eq 1 ]; then
        echo "ipv6"
    else
        echo "ipv4"
    fi
}

while IFS= read -r line || [ -n "$line" ]; do
    # trim
    line=$(echo "$line" | xargs)
    # 如果是空行则清空IP版本和速率限制以及默认SOURCE
    if [ -z "$line" ]; then
        IP_VERSION="$GLOBAL_IP_VERSION"
        RATE="$GLOBAL_RATE"
        DEFAULT_SOURCE="$GLOBAL_SOURCE"
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
    # 如果是!!开头，则设置全局IP版本
    if [[ $line == \!\!* ]]; then
        GLOBAL_IP_VERSION="${line#!!}"
        IP_VERSION="$GLOBAL_IP_VERSION"
        continue
    fi
    # 如果是!开头，则设置使用的IP版本
    if [[ $line == \!* ]]; then
        IP_VERSION="${line#!}"
        continue
    fi
    # 如果是<<开头则设置全局速率限制
    if [[ $line == \<\<* ]]; then
        GLOBAL_RATE="${line#<<}"
        RATE="$GLOBAL_RATE"
        continue
    fi
    # 如果是<开头则设置速录限制
    if [[ $line == \<* ]]; then
        RATE="${line#<}"
        continue
    fi
    # 如果是@@开头则设置全局默认SOURCE
    if [[ $line == @@* ]]; then
        GLOBAL_SOURCE="${line#@@}"
        DEFAULT_SOURCE="$GLOBAL_SOURCE"
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
        HOSTS_IPv4="$HOSTS_IPv4 $DOMAIN"
        ;;
    "ipv6")
        HOSTS_IPv6="$HOSTS_IPv6 $DOMAIN"
        ;;
    "")
        HOSTS_DEFAULT="$HOSTS_DEFAULT $DOMAIN"
        ;;
    *)
        # 按照,分割IP并排序
        IFS=',' read -ra IPS <<<"$IP_VERSION"
        IPS_SORTED=($(printf "%s\n" "${IPS[@]}" | sort))
        bind_key=$(echo "${IPS_SORTED[*]}" | tr ' ' ',')
        
        # 检查IP版本是否一致
        ip_version=$(check_ip_version "$bind_key")
        
        # 在已有的bind组合中查找
        split_var_found=""
        while IFS='=' read -r key value; do
            if [ "$key" = "$bind_key" ]; then
                split_var_found=$(echo "$value" | xargs)
                break
            fi
        done <<<"$used_bind_groups"

        if [ -z "$split_var_found" ]; then
            # 如果这个bind组合是新的
            split_var_name="split_ip_$(echo "$bind_key" | md5sum | cut -c1-8)"
            used_bind_groups=$(echo -e "$used_bind_groups\n$bind_key=$split_var_name")

            # 生成split_clients配置
            total=${#IPS[@]}
            percent=$((100 / total))
            remaining=$((100 % total))

            split_config=""
            for ((i = 0; i < total - 1; i++)); do
                ip="${IPS[$i]}"
                split_config="${split_config}        ${percent}%    ${ip};\n"
            done
            split_config="${split_config}        *      ${IPS[$total - 1]};"

            SPLIT_CLIENTS=$(echo -e "$SPLIT_CLIENTS\n    split_clients \"\$remote_addr\$remote_port\$ssl_preread_server_name\" \$$split_var_name {\n$split_config\n    }")
            split_var_found="$split_var_name"
        fi

        # 使用已存在的split变量
        BINDS=$(echo -e "$BINDS\n        $DOMAIN \$$split_var_found;")
        
        # 根据IP版本添加到对应的HOSTS变量
        if [ "$ip_version" = "ipv4" ]; then
            HOSTS_IPv4_BIND="$HOSTS_IPv4_BIND $DOMAIN"
        else
            HOSTS_IPv6_BIND="$HOSTS_IPv6_BIND $DOMAIN"
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
    DEFAULT_SERVER="# default server
    server {
        $LISTEN_CONFIG
        server_name$HOSTS_DEFAULT;
        ssl_preread on;

        proxy_pass \$source;
    }"
fi

if [ "$HOSTS_IPv4" != "" ]; then
    IPv4_SERVER="# ipv4 server
    server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv4;
        ssl_preread on;
        resolver $DNS ipv4=on ipv6=off;

        proxy_pass \$source;
    }"
fi

if [ "$HOSTS_IPv4_BIND" != "" ]; then
    IPv4_BIND_SERVER="# ipv4 bind server
    server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv4_BIND;
        ssl_preread on;
        resolver $DNS ipv4=on ipv6=off;

        proxy_pass \$source;
        proxy_bind \$bind;
    }"
fi

if [ "$HOSTS_IPv6" != "" ]; then
    IPv6_SERVER="# ipv6 server
    server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv6;
        ssl_preread on;
        resolver $DNS ipv4=off ipv6=on;

        proxy_pass \$source;
    }"
fi

if [ "$HOSTS_IPv6_BIND" != "" ]; then
    IPv6_BIND_SERVER="# ipv6 bind server
    server {
        $LISTEN_CONFIG
        server_name$HOSTS_IPv6_BIND;
        ssl_preread on;
        resolver $DNS ipv4=off ipv6=on;

        proxy_pass \$source;
        proxy_bind \$bind;
    }"
fi

if [ -z "$DISABLE_HTTP" ]; then
    HTTP_LISTEN_CONFIG=""
    for port in $(echo $HTTP_PORTS | tr ',' ' '); do
        port=$(echo $port | xargs)
        if [ -z "$port" ]; then
            continue
        fi
        if [ -z "$HTTP_LISTEN_CONFIG" ]; then
            HTTP_LISTEN_CONFIG="$(echo -e "listen $port default_server reuseport;\n        listen [::]:$port default_server reuseport;")"
        else
            HTTP_LISTEN_CONFIG="$(echo -e "$HTTP_LISTEN_CONFIG\n        listen $port default_server reuseport;\n        listen [::]:$port default_server reuseport;")"
        fi
    done

    HTTP_SERVER="# http server
    server {
        $HTTP_LISTEN_CONFIG
        server_name _;

        return 302 https://\$http_host\$request_uri;
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
    log_format basic '[\$time_local] \$remote_addr:\$remote_port → \$server_addr:\$server_port | \$ssl_preread_server_name|\$ssl_preread_protocol|\$ssl_preread_alpn_protocols | \$bind -> \$upstream_addr | ↑ \$upstream_bytes_sent | ↓ \$upstream_bytes_received | \$session_time s | \$status';
    map \$status \$loggable {
        403 $FORBIDDEN_LOG;
        default 1;
    }
    access_log /var/log/nginx/access.log basic if=\$loggable;
    resolver $DNS ipv4=on ipv6=on;

    $ALLOW

$(BuildPools)
    map \$ssl_preread_server_name \$source {
        hostnames;$SOURCES
        default \$ssl_preread_server_name:443;
    }
    map \$ssl_preread_server_name \$rate {
        hostnames;$RATES
        default 0;
    }
    map \$ssl_preread_server_name \$bind {
        hostnames;$BINDS
        default \$server_addr;
    }

$SPLIT_CLIENTS

    proxy_connect_timeout 15s;
    proxy_timeout 90s;
    proxy_buffer_size 24k;
    tcp_nodelay on;
    preread_timeout 15s;
    resolver_timeout 15s;
    proxy_socket_keepalive on;
    proxy_upload_rate \$rate;
    proxy_download_rate \$rate;
    $DEFAULT_SERVER
    $IPv4_SERVER
    $IPv4_BIND_SERVER
    $IPv6_SERVER
    $IPv6_BIND_SERVER
    # reuseport server and reject all
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
    error_log /dev/null;

    $ALLOW

    $HTTP_SERVER
}
EOF

mv -f $tmp_file $CONFIG_DIR/nginx.conf
