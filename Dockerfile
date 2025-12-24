# QuickJS Docker Image with static compilation benchmark
# Multi-stage build for minimal image size

# Stage 1: Builder
FROM alpine:latest AS builder

# Install build dependencies
RUN set -eux \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    git \
    make \
    gcc \
    musl-dev \
    curl \
    tar \
    xz \
    binutils \
    upx

# Download QuickJS source
RUN set -eux \
    && echo "=== Downloading QuickJS source ===" \
    && curl -L -o /tmp/quickjs.tar.xz https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz \
    && tar -xf /tmp/quickjs.tar.xz -C /tmp/ \
    && mv /tmp/quickjs-* /tmp/quickjs

# Build QuickJS and create static qjs interpreter
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    && make install \
    \
    && echo "=== Creating static qjs interpreter ===" \
    && mkdir -p /benchmark \
    # Build static binary using Makefile
    && make qjs LDFLAGS="-static" \
    && mv qjs /benchmark/qjs-static \
    \
    && echo "=== Verifying static binary ===" \
    && file /benchmark/qjs-static \
    \
    && echo "=== Creating benchmark test ===" \
    && echo "console.log('QuickJS Static Compilation Benchmark Test');" > /benchmark/bench.js \
    && echo "console.log('Version: 2025-09-13');" >> /benchmark/bench.js \
    && echo "console.log('Testing basic operations...');" >> /benchmark/bench.js \
    && echo "const start = Date.now();" >> /benchmark/bench.js \
    && echo "for (let i = 0; i < 1000000; i++) { Math.sqrt(i); }" >> /benchmark/bench.js \
    && echo "const end = Date.now();" >> /benchmark/bench.js \
    && echo "console.log('Time for 1M sqrt operations: ' + (end - start) + 'ms');" >> /benchmark/bench.js \
    && echo "console.log('Static compilation test completed successfully!');" >> /benchmark/bench.js

# Strip and compress static binary for minimal size
RUN set -eux \
    && echo "=== Stripping and compressing static binary ===" \
    && strip -v --strip-all /benchmark/qjs-static \
    && upx --best --lzma /benchmark/qjs-static

# Stage 2: Final Runtime (Minimal)
FROM busybox:musl

# Copy only the essential files for running the benchmark
COPY --from=builder /benchmark /benchmark

# Copy required dynamic loader for compatibility
COPY --from=builder /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1

# Set working directory
WORKDIR /benchmark

# Set entrypoint to run the benchmark using the static qjs interpreter
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
