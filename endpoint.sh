#!/bin/bash

if [ -z "$DOMAINS_FILE" ]; then
    echo "DOMAINS_FILE is not set"
    exit 1
fi

export CONFIG_DIR="/etc/nginx"

if [ ! -f "$DOMAINS_FILE" ]; then
    touch $DOMAINS_FILE
fi

bash /nginx.sh
if [ $? -ne 0 ]; then
    echo "generate nginx.conf failed"
    exit 1
fi
echo "nginx.conf test success"

nginx -t
if [ $? -ne 0 ]; then
    echo "nginx.conf test failed"
    echo "domains content:"
    cat $DOMAINS_FILE
    exit 1
fi

sh /docker-entrypoint.sh "$@" &

while true; do
    inotifywait -e modify $DOMAINS_FILE
    echo "$DOMAINS_FILE changed"
    bash /nginx.sh
    if [ $? -ne 0 ]; then
        echo "generate nginx.conf failed"
        echo "domains content:"
        cat $DOMAINS_FILE
        continue
    fi
    nginx -t && nginx -s reload
    echo "generate nginx.conf success"
done
