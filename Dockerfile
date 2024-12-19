FROM nginx:1.26

COPY nginx.sh /nginx.sh

COPY endpoint.sh /endpoint.sh

RUN chmod +x /nginx.sh /endpoint.sh

RUN apt-get update && \
    apt-get install -y inotify-tools bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app && \
    touch /app/domains.txt

ENV DOMAINS_FILE="/app/domains.txt"

ENV CONFIG_DIR="/etc/nginx"

ENV DNS=""

ENV LISTEN_PORTS="443"

EXPOSE 80 443

ENTRYPOINT ["/endpoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
