#!/bin/bash

set -e

if [ ! -f "domains.txt" ]; then
    echo "domains.txt not found"
    exit 1
fi

# 清空
>AdGuardHome.yaml

# 写入初始内容到AdGuardHome.yaml文件
cat <<EOF >>AdGuardHome.yaml
http:
  pprof:
    port: 6060
    enabled: false
  address: 0.0.0.0:8080
  session_ttl: 720h
users:
  - name: admin
    # adminadmin
    password: \$2a\$10\$epwcV.l4.bGQ9iL69D6dC.WEuPx5Sj6rONoN.XJnr1eW5EFm0DHy2
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
    - h3://dns.google/dns-query
    - quic://unfiltered.adguard-dns.com
  upstream_dns_file: ""
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
    - 2620:fe::10
    - 2620:fe::fe:10
  fallback_dns:
    - https://dns.google/dns-query
    - https://unfiltered.adguard-dns.com/dns-query
  upstream_mode: parallel
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
  enable_dnssec: false
  edns_client_subnet:
    custom_ip: ""
    enabled: true
    use_custom: false
  max_goroutines: 300
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
  hostsfile_enabled: true
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  allow_unencrypted_doh: false
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
querylog:
  dir_path: ""
  ignored: []
  interval: 6h
  size_memory: 1000
  enabled: true
  file_enabled: true
statistics:
  dir_path: ""
  ignored: []
  interval: 6h
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
EOF

# 打开文件并读取每一行
while IFS= read -r line || [[ -n "$line" ]]; do
  if [ -z "$line" ]; then
    continue
  fi
  if [[ $line == \#* ]]; then
    IPS=${line#*#}
    IPS=$(echo $IPS | xargs)
    echo $IPS
    continue
  fi
  if [ -z "$IPS" ]; then
    echo "ip list empty"
    exit 1
  fi

  for IP in $(echo $IPS | sed "s/,/ /g"); do
    IP=$(echo $IP | xargs)
    # 将格式化的行写入到AdGuardHome.yaml文件中
    echo "    - domain: \"$line\"" >>AdGuardHome.yaml
    echo "      answer: $IP" >>AdGuardHome.yaml
    echo "    - domain: \"*.$line\"" >>AdGuardHome.yaml
    echo "      answer: $IP" >>AdGuardHome.yaml
  done
done <"domains.txt"

# 在文件末尾添加内容
cat <<EOF >>AdGuardHome.yaml
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

mkdir -p conf
mv -f AdGuardHome.yaml conf/AdGuardHome.yaml
