#!/bin/bash

if [ -z "$DOMAINS_FILE" ]; then
	echo "DOMAINS_FILE is not set"
	exit 1
fi

export CONFIG_DIR="/etc/nginx"

if [ ! -f "$DOMAINS_FILE" ]; then
	touch $DOMAINS_FILE
fi

# 从domains.txt中提取所有使用的网卡名称
extract_devices_from_domains() {
	local domains_file="$1"
	local devices=""

	if [ ! -f "$domains_file" ]; then
		echo ""
		return
	fi

	# 查找所有device:xxx的配置
	while IFS= read -r line || [ -n "$line" ]; do
		line=$(echo "$line" | xargs)

		# 检查是否是!或!!开头的行
		if [[ $line != \!* ]]; then
			continue

		fi

		local config="${line#!}"
		config="${config#!}" # 再去掉一次，处理!!的情况

		# 提取所有device:xxx配置
		local found_devices=$(echo "$config" | grep -oP 'device:\K[a-zA-Z0-9_-]+' || true)

		if [ -n "$found_devices" ]; then
			for dev in $found_devices; do
				# 检查是否已存在
				if [[ ! "$devices" =~ (^|,)"$dev"(,|$) ]]; then
					if [ -z "$devices" ]; then
						devices="$dev"
					else
						devices="$devices,$dev"
					fi
				fi
			done
		fi
	done <"$domains_file"

	echo "$devices"
}

# 更新网卡列表文件
update_devices_file() {
	local devices=$(extract_devices_from_domains "$DOMAINS_FILE")
	if [ -n "$devices" ]; then
		echo "$devices" >"$CONFIG_DIR/used_devices.txt"
	else
		rm -f "$CONFIG_DIR/used_devices.txt"
	fi
}

# 获取网卡的IP地址缓存
get_device_ips_hash() {
	local devices_file="$CONFIG_DIR/used_devices.txt"
	if [ ! -f "$devices_file" ]; then
		echo ""
		return
	fi

	local devices=$(cat "$devices_file" | tr ',' ' ')
	local hash=""

	for device in $devices; do
		if [ -d "/sys/class/net/$device" ]; then
			local ipv4=$(ip -4 addr show dev "$device" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
			local ipv6=$(ip -6 addr show dev "$device" scope global 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | head -n 1)
			hash="${hash}${device}:${ipv4}:${ipv6};"
		fi
	done

	echo "$hash"
}

# 首次生成网卡列表和nginx配置
echo "Extracting devices from domains file..."
update_devices_file

echo "Generating nginx configuration..."
bash /nginx.sh $NGINX_ARGS
if [ $? -ne 0 ]; then
	echo "generate nginx.conf failed"
	exit 1
fi
echo "nginx.conf generated successfully"

nginx -t
if [ $? -ne 0 ]; then
	echo "nginx.conf test failed"
	echo "domains content:"
	cat $DOMAINS_FILE
	exit 1
fi
echo "nginx.conf test passed"

# 初始化IP地址哈希
DEVICE_IPS_HASH=$(get_device_ips_hash)

# 监控domains文件变更
(
	while true; do
		inotifywait -e modify $DOMAINS_FILE
		echo "$DOMAINS_FILE changed, updating configuration..."

		# 重新提取网卡列表
		update_devices_file

		# 重新生成nginx配置
		bash /nginx.sh $NGINX_ARGS
		if [ $? -ne 0 ]; then
			echo "generate nginx.conf failed"
			echo "domains content:"
			cat $DOMAINS_FILE
			continue
		fi
		echo "generate nginx.conf success"

		# 更新设备IP哈希
		DEVICE_IPS_HASH=$(get_device_ips_hash)

		nginx -t && nginx -s reload
	done
) &

# 监控网卡IP变更
(
	while true; do
		sleep 3

		NEW_HASH=$(get_device_ips_hash)

		if [ "$NEW_HASH" != "$DEVICE_IPS_HASH" ] && [ -n "$NEW_HASH" ]; then
			echo "Network device IP changed, regenerating config..."
			bash /nginx.sh $NGINX_ARGS
			if [ $? -ne 0 ]; then
				echo "generate nginx.conf failed after device change"
				continue
			fi
			echo "generate nginx.conf success after device change"
			if nginx -t; then
				nginx -s reload
				DEVICE_IPS_HASH="$NEW_HASH"
				echo "nginx reloaded successfully"
			else
				echo "nginx config test failed after device change"
			fi
		fi
	done
) &

sh /docker-entrypoint.sh "$@"
