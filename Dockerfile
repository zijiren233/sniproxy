FROM nginx:1.26

COPY nginx.sh /nginx.sh

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /nginx.sh /entrypoint.sh

RUN apt-get update && \
    apt-get install -y inotify-tools bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app

ENV DOMAINS_FILE="/app/domains.txt"

ENV DNS=""

ENV LISTEN_PORTS="443"

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
