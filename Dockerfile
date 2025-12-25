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
    # First, find and copy the entire bench-v8 directory
    && echo "=== Searching for bench-v8 directory ===" \
    && BENCH_DIR=$(find /tmp -type d -name "*bench-v8*" 2>/dev/null | head -1) \
    && if [ -n "$BENCH_DIR" ]; then \
        echo "Found bench-v8 directory at: $BENCH_DIR" \
        && echo "=== Listing source directory contents ===" \
        && ls -la "$BENCH_DIR"/ \
        && echo "=== Copying entire bench-v8 directory ===" \
        && cp -r "$BENCH_DIR"/* /benchmark/bench-v8/ 2>/dev/null || echo "Some files may have failed to copy"; \
    else \
        echo "ERROR: Could not find bench-v8 directory" \
        && find /tmp -type d -name "*quickjs*" | sort \
        && find /tmp -type d | grep -i bench \
        && exit 1; \
    fi \
    \
    # Verify we got the benchmark files
    && echo "=== Benchmark files copied ===" \
    && ls -la /benchmark/bench-v8/ \
    && echo "=== Checking essential files ===" \
    && (test -f /benchmark/bench-v8/bench.js && echo "✓ bench.js exists" || echo "✗ bench.js missing") \
    && (test -f /benchmark/bench-v8/base.js && echo "✓ base.js exists" || echo "✗ base.js missing") \
    && (test -f /benchmark/bench-v8/run_harness.js && echo "✓ run_harness.js exists" || echo "✗ run_harness.js missing") \
    \
    # Ensure bench.js exists (use run_harness.js if needed)
    && if [ ! -f /benchmark/bench-v8/bench.js ] && [ -f /benchmark/bench-v8/run_harness.js ]; then \
        echo "Using run_harness.js as bench.js..." \
        && cp /benchmark/bench-v8/run_harness.js /benchmark/bench-v8/bench.js; \
    fi \
    \
    # Show bench.js content for debugging
    && echo "=== First 20 lines of bench.js ===" \
    && head -20 /benchmark/bench-v8/bench.js 2>/dev/null || echo "ERROR: Cannot read bench.js" \
    \
    # Test run the benchmark to ensure it works
    # && echo "=== Testing benchmark execution ===" \
    # && cd /benchmark/bench-v8 \
    # && /benchmark/qjs-static -e "console.log('QuickJS version test');" 2>&1 \
    # && echo "QuickJS interpreter test passed" \
    # \
    # Final check - bench.js must exist
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
# COPY --from=builder /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1

# Set working directory to where bench.js is located
WORKDIR /benchmark/bench-v8

# Set entrypoint to run the bench-v8 benchmark using the static qjs interpreter
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
