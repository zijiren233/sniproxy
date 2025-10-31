#!/bin/bash

set -e

if [ -z "$DOMAINS_FILE" ]; then
	DOMAINS_FILE="domains.txt"
fi
if [ ! -f "$DOMAINS_FILE" ]; then
	echo "adguardhome: $DOMAINS_FILE not found"
	exit 1
fi
if [ -z "$CONFIG_DIR" ]; then
	CONFIG_DIR="./conf"
fi
mkdir -p $CONFIG_DIR

REWRITES=""
IPS=""

# 读取文件并构建rewrites
while IFS= read -r line || [ -n "$line" ]; do
	# trim
	line=$(echo "$line" | xargs)
	# 跳过空行
	if [ -z "$line" ]; then
		continue
	fi
	# 跳过注释行 `//`
	if [[ $line == //* ]]; then
		continue
	fi
	# 跳过nginx规则 `!`
	if [[ $line == \!* ]]; then
		continue
	fi
	# 跳过nginx规则 `<`
	if [[ $line == \<* ]]; then
		continue
	fi
	# 跳过nginx规则 `&`
	if [[ $line == \&* ]]; then
		continue
	fi
	# 跳过@开头
	if [[ $line == @* ]]; then
		continue
	fi
	# 跳过nginx多行注释块 ``` 开头
	if [[ $line == "\`\`\`"* ]]; then
		while IFS= read -r command_line; do
			if [[ $(echo "$command_line" | xargs) == "\`\`\`" ]]; then
				break
			fi
		done
		continue
	fi
	# 跳过nginx单行注释块 ` 结尾
	if [[ $line == *"\`" ]]; then
		continue
	fi
	# 如果是^开头的则是设置adguardhome的上游DNS
	if [[ $line == ^* ]]; then
		line="${line#^}"
		UPSTREAM_DNS=$line
		continue
	fi
	# 如果是$开头，则设置admin密码
	if [[ $line == \$* ]]; then
		ADMIN_PASS="${line#$}"
		continue
	fi
	# 检查是否以=开头，如果是则去掉=
	if [[ $line == =* ]]; then
		line="${line#=}"
	fi
	# 如果是adguardhome规则，则获取IP列表 `#`
	if [[ $line == \#* ]]; then
		IPS=${line#*#}
		IPS=$(echo $IPS | xargs)
		continue
	fi
	if [ -z "$IPS" ]; then
		echo "adguardhome: ip list empty" 1>&2
		exit 1
	fi

	for IP in $(echo $IPS | sed "s/,/ /g"); do
		IP=$(echo $IP | xargs)
		if [ -z "$IP" ]; then
			continue
		fi
		# 把line按照@分割，第一个为域名，不需要后面的，且需要trim
		DOMAIN=$(echo $line | awk -F@ '{print $1}' | xargs)
		# 将格式化的行添加到REWRITES变量
		if [ -z "$REWRITES" ]; then
			REWRITES="$(echo -e "    - domain: \"$DOMAIN\"\n      answer: $IP\n    - domain: \"*.$DOMAIN\"\n      answer: $IP")"
		else
			REWRITES="$(echo -e "$REWRITES\n    - domain: \"$DOMAIN\"\n      answer: $IP\n    - domain: \"*.$DOMAIN\"\n      answer: $IP")"
		fi
	done
done <"$DOMAINS_FILE"

if [ -z "$UPSTREAM_DNS" ]; then
	UPSTREAM_DNS="h3://dns.google/dns-query,https://dns11.quad9.net/dns-query"
fi
if [ -z "$FALLBACK_DNS" ]; then
	FALLBACK_DNS="https://dns.google/dns-query,tls://dns11.quad9.net"
fi
if [ -z "$BOOTSTRAP_DNS" ]; then
	BOOTSTRAP_DNS="9.9.9.10,149.112.112.10,2620:fe::10,2620:fe::fe:10"
fi
if [ -z "$ADMIN_USER" ]; then
	ADMIN_USER="admin"
fi
if [ -z "$ADMIN_PASS" ]; then
	ADMIN_PASS="adminadmin"
fi

if [ "$ADMIN_PASS" == "adminadmin" ]; then
	PASSWORD_HASH="\$2a\$10\$epwcV.l4.bGQ9iL69D6dC.WEuPx5Sj6rONoN.XJnr1eW5EFm0DHy2"
else
	PASSWORD_HASH=$(htpasswd -B -C 10 -n -b $ADMIN_USER $ADMIN_PASS | awk -F':' '{print $2}')
fi

readonly tmp_file=$(mktemp)

cat <<EOF >$tmp_file
http:
  pprof:
    port: 6060
    enabled: false
  address: 0.0.0.0:8080
  session_ttl: 720h
users:
  - name: $ADMIN_USER
    password: $PASSWORD_HASH
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ""
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  anonymize_client_ip: false
  ratelimit: 0
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
$(echo "$UPSTREAM_DNS" | tr ',' '\n' | sed 's/^/    - /')
  upstream_dns_file: ""
  bootstrap_dns:
$(echo "$BOOTSTRAP_DNS" | tr ',' '\n' | sed 's/^/    - /')
  fallback_dns:
$(echo "$FALLBACK_DNS" | tr ',' '\n' | sed 's/^/    - /')
  upstream_mode: load_balance
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  cache_size: 0
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: true
  edns_client_subnet:
    custom_ip: ""
    enabled: true
    use_custom: false
  max_goroutines: 1024
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_prefer_ipv6: false
  upstream_timeout: 10s
  private_networks: []
  use_private_ptr_resolvers: false
  local_ptr_upstreams: []
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: false
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  allow_unencrypted_doh: true
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
querylog:
  dir_path: ""
  ignored: []
  interval: 1h
  size_memory: 4096
  enabled: true
  file_enabled: false
statistics:
  dir_path: ""
  ignored: []
  interval: 3h
  enabled: true
filters: []
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
filtering:
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_services:
    schedule:
      time_zone: UTC
    ids: []
  protection_disabled_until: null
  safe_search:
    enabled: false
    bing: true
    duckduckgo: true
    google: true
    pixabay: true
    yandex: true
    youtube: true
  blocking_mode: default
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites:
$REWRITES
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  filters_update_interval: 0
  blocked_response_ttl: 10
  filtering_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: false
    dhcp: true
    hosts: true
  persistent: []
log:
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 28
EOF

mv -f $tmp_file $CONFIG_DIR/AdGuardHome.yaml
