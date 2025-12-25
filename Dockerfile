FROM alpine:latest

# 安装依赖并构建
RUN apk add --no-cache make gcc musl-dev curl tar xz && \
    curl -L https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz | tar -xJf - -C /tmp && \
    cd /tmp/quickjs-* && make -j$(nproc) && \
    curl -L https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz | tar -xJf - -C /tmp && \
    mkdir -p /bench && cp -r /tmp/quickjs-*/tests/bench-v8/* /bench/ && \
    cp /tmp/quickjs-*/qjs /bench/

# 创建运行脚本
RUN echo '#!/bin/sh' > /bench/run.sh && \
    echo 'echo "=== QuickJS Bench-V8 Benchmark ==="' >> /bench/run.sh && \
    echo 'cd /bench && ./qjs combined.js' >> /bench/run.sh && \
    chmod +x /bench/run.sh

WORKDIR /bench
CMD ["/bin/sh", "/bench/run.sh"]
