# QuickJS Docker Image - Minimal Build with Benchmarks
# Optimized for size and performance

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

# Download QuickJS source (minimal - no extras needed for basic benchmark)
RUN set -eux \
    && echo "=== Downloading QuickJS source ===" \
    && curl -L -o /tmp/quickjs.tar.xz https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz \
    && tar -xf /tmp/quickjs.tar.xz -C /tmp/ \
    && mv /tmp/quickjs-* /tmp/quickjs

# Build minimal QuickJS with optimized flags
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS (minimal configuration) ===" \
    # Build with optimization flags for minimal size
    && make -j$(nproc) \
        CFLAGS="-Os -ffunction-sections -fdata-sections" \
        LDFLAGS="-Wl,--gc-sections -static" \
    \
    && echo "=== Creating minimal static qjs interpreter ===" \
    && mkdir -p /benchmark \
    # Build static binary with minimal features
    && make qjs LDFLAGS="-static -Wl,--gc-sections" \
    && mv qjs /benchmark/qjs-static \
    \
    && echo "=== Verifying static binary ===" \
    && file /benchmark/qjs-static \
    && /benchmark/qjs-static -e "print('QuickJS works!'); print('Version:', typeof quickjs)" \
    \
    && echo "=== Creating minimal benchmark ===" \
    # Create a simple, working benchmark that doesn't rely on external harness
    && cat > /benchmark/bench.js << 'EOF'
// Minimal QuickJS benchmark
const startTime = Date.now();
let iterations = 0;

function fibonacci(n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

// Run benchmark
const testStart = Date.now();
const result = fibonacci(28); // Standard benchmark test
const testEnd = Date.now();

iterations = 1;

print("=== QuickJS Benchmark Results ===");
print("Fibonacci(28) =", result);
print("Execution time:", (testEnd - testStart), "ms");
print("Iterations:", iterations);
print("Throughput:", ((testEnd - testStart) / iterations).toFixed(2), "ms/iter");
print("Total time:", (Date.now() - startTime), "ms");
EOF

# Strip and compress for maximum minimization
RUN set -eux \
    && echo "=== Minimizing binary ===" \
    && strip -v --strip-all --strip-unneeded /benchmark/qjs-static \
    && upx --best --lzma /benchmark/qjs-static \
    \
    && echo "=== Final binary size ===" \
    && ls -lh /benchmark/qjs-static

# Stage 2: Final Runtime (Ultra-minimal)
FROM scratch
# FROM busybox:musl

# Copy only the absolute essentials
COPY --from=builder /benchmark/qjs-static /qjs
COPY --from=builder /benchmark/bench.js /bench.js

# Set entrypoint
ENTRYPOINT ["/qjs", "/bench.js"]
