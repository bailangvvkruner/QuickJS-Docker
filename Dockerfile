# QuickJS Docker Image - Minimal Build with Official Bench-V8 Benchmark
# Optimized for size while maintaining official benchmark functionality

# Stage 1: Builder
FROM alpine:latest AS builder

# Install minimal build dependencies
RUN set -eux \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    make \
    gcc \
    musl-dev \
    curl \
    tar \
    xz \
    binutils \
    upx

# Download QuickJS source and official extras (contains bench-v8)
RUN set -eux \
    && echo "=== Downloading QuickJS source ===" \
    && curl -L -o /tmp/quickjs.tar.xz https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz \
    && tar -xf /tmp/quickjs.tar.xz -C /tmp/ \
    && mv /tmp/quickjs-* /tmp/quickjs \
    \
    && echo "=== Downloading QuickJS extras (contains official bench-v8) ===" \
    && curl -L -o /tmp/quickjs-extras.tar.xz https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz \
    && tar -xf /tmp/quickjs-extras.tar.xz -C /tmp/

# Extract and prepare bench-v8 benchmark files
RUN set -eux \
    && echo "=== Extracting official bench-v8 benchmark ===" \
    && mkdir -p /benchmark/bench-v8 \
    \
    # Find the bench-v8 directory in the extracted extras
    && BENCH_DIR=$(find /tmp -type d -name "*bench-v8*" 2>/dev/null | head -1) \
    && if [ -n "$BENCH_DIR" ]; then \
        echo "Found bench-v8 at: $BENCH_DIR" \
        && ls -la "$BENCH_DIR"/ \
        && cp -r "$BENCH_DIR"/* /benchmark/bench-v8/ 2>/dev/null || true; \
    else \
        echo "ERROR: bench-v8 directory not found" \
        && find /tmp -type d -name "*quickjs*" \
        && exit 1; \
    fi \
    \
    && echo "=== Verifying benchmark files ===" \
    && ls -la /benchmark/bench-v8/ \
    && test -f /benchmark/bench-v8/bench.js && echo "✓ bench.js found" || echo "✗ bench.js missing" \
    && test -f /benchmark/bench-v8/base.js && echo "✓ base.js found" || echo "✗ base.js missing" \
    && test -f /benchmark/bench-v8/run_harness.js && echo "✓ run_harness.js found" || echo "✗ run_harness.js missing"

# Build QuickJS static binary
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    \
    && echo "=== Creating static qjs binary ===" \
    && make qjs LDFLAGS="-static" \
    && mv qjs /benchmark/qjs-static \
    \
    && echo "=== Verifying binary ===" \
    && file /benchmark/qjs-static \
    && /benchmark/qjs-static -e "print('QuickJS static binary ready');"

# Minimize the binary
RUN set -eux \
    && echo "=== Minimizing binary ===" \
    && strip -v --strip-all --strip-unneeded /benchmark/qjs-static \
    && upx --best --lzma /benchmark/qjs-static \
    \
    && echo "=== Final binary size ===" \
    && ls -lh /benchmark/qjs-static

# Stage 2: Final Runtime
FROM busybox:musl

# Copy essential files
COPY --from=builder /benchmark/qjs-static /qjs
COPY --from=builder /benchmark/bench-v8/ /bench-v8/

# Set working directory to bench-v8 (where bench.js expects to run)
WORKDIR /bench-v8

# Run the official bench-v8 benchmark
ENTRYPOINT ["/qjs", "bench.js"]
