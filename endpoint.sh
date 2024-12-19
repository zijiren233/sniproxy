#!/bin/sh

if [ -z "$DOMAINS_FILE" ]; then
    echo "DOMAINS_FILE is not set"
    exit 1
fi

sh /nginx.sh || (echo "generate nginx.conf failed" && exit 1)

sh /docker-entrypoint.sh $@ &

while inotifywait -e modify $DOMAINS_FILE; do
    echo "$DOMAINS_FILE changed"
    sh /nginx.sh || echo "generate nginx.conf failed"
done
