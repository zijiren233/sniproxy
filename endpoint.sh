#!/bin/bash

if [ -z "$DOMAINS_FILE" ]; then
    echo "DOMAINS_FILE is not set"
    exit 1
fi

bash /nginx.sh
if [ $? -ne 0 ]; then
    echo "generate nginx.conf failed"
    exit 1
fi

sh /docker-entrypoint.sh $@ &

while inotifywait -e modify $DOMAINS_FILE; do
    echo "$DOMAINS_FILE changed"
    bash /nginx.sh || echo "generate nginx.conf failed"
done
