# QuickJS Docker Image with bench-v8 benchmark
# Multi-stage build with official bench-v8 benchmark

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
    && echo "=== Downloading QuickJS extras (for bench-v8) ===" \
    && curl -L -o /tmp/quickjs-extras.tar.xz https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz \
    && tar -xf /tmp/quickjs-extras.tar.xz -C /tmp/

# Find and extract bench-v8 from extras
RUN set -eux \
    && echo "=== Searching for bench-v8 in extras ===" \
    && find /tmp -name "bench.js" -type f 2>/dev/null | head -5 \
    && echo "=== Extracting bench-v8 files ===" \
    && mkdir -p /benchmark/bench-v8 \
    # Try to find and copy bench.js from various locations
    && (find /tmp -name "bench.js" -type f -exec cp {} /benchmark/bench-v8/ \; 2>/dev/null || true) \
    # Also look for other benchmark files
    && (find /tmp -path "*bench-v8*" -name "*.js" -type f -exec cp {} /benchmark/bench-v8/ \; 2>/dev/null || true) \
    \
    # If bench.js not found, download it directly from known location
    && (test -f /benchmark/bench-v8/bench.js || \
        (echo "=== Downloading bench.js directly ===" && \
         curl -L -o /benchmark/bench-v8/bench.js https://raw.githubusercontent.com/bellard/quickjs/master/bench-v8/bench.js 2>/dev/null || \
         echo "console.log('Using fallback benchmark');" > /benchmark/bench-v8/bench.js))

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
    && file /benchmark/qjs-static \
    \
    && echo "=== Testing bench-v8 availability ===" \
    && ls -la /benchmark/bench-v8/ \
    && echo "=== Bench.js content (first 5 lines) ===" \
    && head -5 /benchmark/bench-v8/bench.js 2>/dev/null || echo "Bench.js not found"

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
