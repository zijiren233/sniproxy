FROM nginx:1.26.3 as builder

RUN apt-get update && apt-get install -y \
    apt-transport-https \
    build-essential \
    libpcre3-dev \
    zlib1g-dev \
    libssl-dev \
    wget \
    git \
    cmake \
    autoconf \
    libtool

RUN git clone https://github.com/oowl/ngx_stream_socks_module /usr/src/ngx_stream_socks_module

RUN wget https://nginx.org/download/nginx-1.26.3.tar.gz -O /tmp/nginx.tar.gz \
    && tar -zxvf /tmp/nginx.tar.gz -C /usr/src/ \
    && mv /usr/src/nginx-1.26.3 /usr/src/nginx

RUN cd /usr/src/nginx \
    && ./configure --with-compat --with-stream --add-dynamic-module=/usr/src/ngx_stream_socks_module \
    && make modules -j$(nproc)

FROM nginx:1.26.3

COPY --from=builder /usr/src/nginx/objs/ngx_stream_socks_module.so /usr/lib/nginx/modules/

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

ENV WORKER_CONNECTIONS=""

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
