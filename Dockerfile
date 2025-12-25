# 构建阶段
FROM alpine:latest AS builder

RUN set -eux \
    && FILENAME=qjs \
    && apk add --no-cache --no-scripts --virtual .build-deps \
        make \
        gcc \
        musl-dev \
        curl \
        tar \
        xz \
        binutils \
    # 尝试安装 upx，如果不可用则继续（某些架构可能不支持）
    \
    && apk add --no-cache --no-scripts --virtual .build-deps \
        upx 2>/dev/null || echo "upx not available, skipping compression" \
    \
    && curl -L https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz | tar -xJf - -C /tmp \
    && cd /tmp/quickjs-* \
    && make -j$(nproc) $FILENAME LDFLAGS="-static" \
    && strip --strip-all $FILENAME \
    && (upx --best $FILENAME 2>/dev/null || echo "upx compression skipped") \
    && mv $FILENAME /qjs-static \
    \
    && curl -L https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz | tar -xJf - -C /tmp \
    && mkdir /bench && cp -r /tmp/quickjs-*/tests/bench-v8/* /bench/

# 运行阶段 - 最小化
FROM scratch
# FROM alpine:latest
# FROM busybox:musl

COPY --from=builder /qjs-static /qjs
COPY --from=builder /bench/ /bench/

WORKDIR /bench

ENTRYPOINT ["/qjs", "combined.js"]
