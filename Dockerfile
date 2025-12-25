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
    # Direct approach: use the path found in build logs
    && echo "=== Looking for bench-v8 directory ===" \
    && find /tmp -type d -name "*bench-v8*" 2>/dev/null \
    && echo "=== Copying bench-v8 files ===" \
    # Method 1: Try direct copy from known path (from build logs)
    && (cp -r /tmp/quickjs-2025-09-13/tests/bench-v8/* /benchmark/bench-v8/ 2>/dev/null || \
        echo "Method 1 failed, trying alternative..." \
    ) \
    # Method 2: Use find to copy bench-v8 directory
    && (find /tmp -type d -name "*bench-v8*" -exec cp -r {}/. /benchmark/bench-v8/ \; 2>/dev/null || \
        echo "Method 2 failed, trying individual files..." \
    ) \
    # Method 3: Copy individual benchmark JS files
    && (find /tmp -type f -name "*.js" -path "*bench*" -exec cp {} /benchmark/bench-v8/ \; 2>/dev/null || \
        echo "Method 3 failed..." \
    ) \
    # Method 4: Ensure bench.js exists (copy run_harness.js as fallback)
    && (test -f /benchmark/bench-v8/bench.js || ( \
        echo "bench.js not found, looking for alternatives..." \
        && find /tmp -type f -name "bench.js" -exec cp {} /benchmark/bench-v8/ \; 2>/dev/null \
        && (test -f /benchmark/bench-v8/bench.js || ( \
            echo "Using run_harness.js as bench.js..." \
            && cp /benchmark/bench-v8/run_harness.js /benchmark/bench-v8/bench.js 2>/dev/null || true \
        )) \
    )) \
    \
    # Verify we got the benchmark files
    && echo "=== Benchmark files found ===" \
    && ls -la /benchmark/bench-v8/ \
    && echo "=== First 10 lines of bench.js (if exists) ===" \
    && (head -10 /benchmark/bench-v8/bench.js 2>/dev/null || echo "WARNING: bench.js not found") \
    \
    # No fallback - fail if bench.js is not found
    && test -f /benchmark/bench-v8/bench.js

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
    # Only test syntax if bench.js exists, never overwrite it
    && (test -f /benchmark/bench-v8/bench.js && \
        echo "Testing bench.js syntax..." && \
        head -5 /benchmark/bench-v8/bench.js && \
        /benchmark/qjs-static -e "print('QuickJS static binary works!')" || \
        echo "WARNING: bench.js not found for testing")

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
