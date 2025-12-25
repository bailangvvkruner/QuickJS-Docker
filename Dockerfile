# 构建阶段
FROM alpine:latest AS builder
RUN apk add --no-cache make gcc musl-dev curl tar xz
RUN curl -L https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz | tar -xJf - -C /tmp && \
    cd /tmp/quickjs-* && make -j$(nproc) qjs LDFLAGS="-static" && \
    strip qjs && \
    mv qjs /qjs-static
RUN curl -L https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz | tar -xJf - -C /tmp && \
    mkdir /bench && cp -r /tmp/quickjs-*/tests/bench-v8/* /bench/

# 运行阶段 - 最小化
# FROM scratch
# FROM alpine:latest
FROM busybox:musl
COPY --from=builder /qjs-static /qjs
COPY --from=builder /bench/ /bench/
WORKDIR /bench
ENTRYPOINT ["/qjs", "combined.js"]
