# 构建阶段
FROM alpine:latest AS builder

RUN set -eux && apk add --no-cache --no-scripts --virtual .build-deps \
    make \
    gcc \
    musl-dev \
    curl \
    tar \
    xz \
    binutils \
    \
    # 安装 upx（仅在支持的架构上）
    # upx 在某些架构（如 s390x）上不可用，因此我们使用条件安装
    && if apk info upx >/dev/null 2>&1; then \
        apk add --no-cache upx && \
        echo "upx installed successfully"; \
    else \
        echo "upx not available for this architecture, skipping"; \
    fi \
    \
    && curl -L https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz | tar -xJf - -C /tmp \
    && cd /tmp/quickjs-* \
    && make -j$(nproc) qjs LDFLAGS="-static" \
    && strip --strip-all qjs \
    && if command -v upx >/dev/null 2>&1; then \
        upx --best qjs && echo "Binary compressed with upx"; \
    else \
        echo "upx not available, binary not compressed"; \
    fi \
    && mv qjs /qjs-static \
    && curl -L https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz | tar -xJf - -C /tmp \
    && mkdir /bench \
    && cp -r /tmp/quickjs-*/tests/bench-v8/* /bench/

# 运行阶段 - 最小化
FROM scratch
# FROM alpine:latest
# FROM busybox:musl
COPY --from=builder /qjs-static /qjs
COPY --from=builder /bench/ /bench/
WORKDIR /bench
ENTRYPOINT ["/qjs", "combined.js"]
