# QuickJS Docker Image - Official Bench-V8 Benchmark
# 使用官方QuickJS基准测试，确保测试结果的公信力

# Stage 1: Builder
FROM alpine:latest AS builder

# Install build dependencies
RUN set -eux \
    && apk add --no-cache --no-scripts --virtual .build-deps \
    make \
    gcc \
    musl-dev \
    curl \
    tar \
    xz

# Download official QuickJS source and extras
RUN set -eux \
    && echo "=== Downloading QuickJS source ===" \
    && curl -L -o /tmp/quickjs.tar.xz https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz \
    && tar -xf /tmp/quickjs.tar.xz -C /tmp/ \
    && mv /tmp/quickjs-* /tmp/quickjs \
    \
    && echo "=== Downloading QuickJS extras (contains official bench-v8) ===" \
    && curl -L -o /tmp/quickjs-extras.tar.xz https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz \
    && tar -xf /tmp/quickjs-extras.tar.xz -C /tmp/

# Extract official bench-v8 benchmark
RUN set -eux \
    && echo "=== Extracting official bench-v8 ===" \
    && mkdir -p /benchmark \
    && cp -r /tmp/quickjs-2025-09-13/tests/bench-v8/* /benchmark/ \
    \
    && echo "=== Official bench-v8 files ===" \
    && ls -la /benchmark/ \
    && echo "=== README content ===" \
    && head -20 /benchmark/README.txt 2>/dev/null || echo "No README"

# Build QuickJS and create static binary
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    \
    && echo "=== Creating static qjs binary ===" \
    && make qjs LDFLAGS="-static" \
    && mv qjs /benchmark/qjs-static \
    \
    && echo "=== Verifying binary exists ===" \
    && ls -la /benchmark/ \
    && test -f /benchmark/qjs-static && echo "✓ qjs-static exists" || echo "✗ qjs-static missing" \
    \
    && echo "=== Minimizing binary ===" \
    && strip --strip-all --strip-unneeded /benchmark/qjs-static \
    && apk add --no-cache upx \
    && upx --best --lzma /benchmark/qjs-static \
    \
    && echo "=== Final binary size ===" \
    && ls -lh /benchmark/qjs-static

# Create proper bench.js wrapper for official benchmark
RUN set -eux \
    && echo "=== Creating official benchmark runner ===" \
    && cat > /benchmark/bench.js << 'EOF'
#!/usr/bin/env qjs
// Official QuickJS bench-v8 benchmark runner

// Set up the benchmark environment
var base = {
    time: function() { return Date.now(); },
    print: print
};

try {
    print("=== QuickJS Official Bench-V8 Benchmark ===");
    print("Loading benchmark infrastructure...");
    
    // Load base.js first
    std.load("/benchmark/base.js");
    
    print("Running benchmark suite...");
    
    // The combined.js contains all the benchmark tests
    // It will automatically run when loaded
    std.load("/benchmark/combined.js");
    
    print("Benchmark completed!");
    
} catch(e) {
    print("Error running benchmark: " + e);
    if (e.stack) {
        print("Stack trace: " + e.stack);
    }
}
EOF

# Make executable
RUN chmod +x /benchmark/bench.js

# Also create a simple test to verify the binary works
RUN set -eux \
    && echo "=== Testing binary ===" \
    && /benchmark/qjs-static -e "print('QuickJS binary test: OK'); print('Version:', typeof quickjs !== 'undefined' ? 'available' : 'standard');"

# Stage 2: Runtime
FROM busybox:musl

# Copy benchmark files and binary
COPY --from=builder /benchmark/ /benchmark/

# Set working directory
WORKDIR /benchmark

# Run official bench-v8
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
