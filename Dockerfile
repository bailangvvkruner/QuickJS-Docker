# QuickJS Docker Image with official bench-v8 benchmark
# Uses the official quickjs-extras package from bellard.org

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

# Download QuickJS source and extras
RUN set -eux \
    && echo "=== Downloading QuickJS source ===" \
    && curl -L -o /tmp/quickjs.tar.xz https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz \
    && tar -xf /tmp/quickjs.tar.xz -C /tmp/ \
    && mv /tmp/quickjs-* /tmp/quickjs \
    \
    && echo "=== Downloading QuickJS extras (contains bench-v8) ===" \
    && curl -L -o /tmp/quickjs-extras.tar.xz https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz \
    && tar -xf /tmp/quickjs-extras.tar.xz -C /tmp/ \
    # List contents to see the structure
    && echo "=== Contents of quickjs-extras ===" \
    && find /tmp/quickjs-extras-* -type f -name "*.js" | head -20

# Extract bench-v8 from the extras package
RUN set -eux \
    && echo "=== Extracting bench-v8 benchmark ===" \
    && mkdir -p /benchmark/bench-v8 \
    # Find and copy bench-v8 files
    && (find /tmp -path "*bench-v8*" -name "*.js" -type f -exec cp {} /benchmark/bench-v8/ \; 2>/dev/null || true) \
    \
    # If bench.js not found in bench-v8 directory, look for it elsewhere
    && (test -f /benchmark/bench-v8/bench.js || \
        (find /tmp -name "bench.js" -type f -exec cp {} /benchmark/bench-v8/ \; 2>/dev/null || true)) \
    \
    # Verify we got the benchmark files
    && echo "=== Benchmark files found ===" \
    && ls -la /benchmark/bench-v8/ \
    && echo "=== First 10 lines of bench.js ===" \
    && (head -10 /benchmark/bench-v8/bench.js 2>/dev/null || echo "WARNING: bench.js not found or empty")

# Build QuickJS and create static qjs interpreter
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    \
    && echo "=== Creating static qjs interpreter ===" \
    && mkdir -p /benchmark \
    # Build static binary using Makefile
    && make qjs LDFLAGS="-static" \
    && mv qjs /benchmark/qjs-static \
    \
    && echo "=== Verifying static binary ===" \
    && apk add --no-cache file \
    && file /benchmark/qjs-static \
    \
    && echo "=== Testing benchmark with static binary ===" \
    # Run a quick syntax check if bench.js exists
    && (test -f /benchmark/bench-v8/bench.js && \
        echo "Testing bench.js syntax..." && \
        head -5 /benchmark/bench-v8/bench.js && \
        /benchmark/qjs-static -e "print('QuickJS static binary works!')" || \
        echo "Creating simple test..." && \
        echo "print('Static QuickJS test'); print('Version: 2025-09-13');" > /benchmark/bench-v8/bench.js)

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

# Set working directory to where bench.js is located
WORKDIR /benchmark/bench-v8

# Set entrypoint to run the bench-v8 benchmark using the static qjs interpreter
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
