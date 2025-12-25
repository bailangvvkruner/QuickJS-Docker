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
    && ls -la /benchmark/

# Build QuickJS
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    \
    && echo "=== Creating static qjs ===" \
    && make qjs LDFLAGS="-static" \
    && mv qjs /benchmark/qjs-static \
    \
    && echo "=== Minimizing binary ===" \
    && strip --strip-all --strip-unneeded /benchmark/qjs-static \
    && apk add --no-cache upx \
    && upx --best --lzma /benchmark/qjs-static \
    \
    && echo "=== Final binary size ===" \
    && ls -lh /benchmark/qjs-static

# Create proper bench.js that works with official structure
RUN set -eux \
    && echo "=== Creating benchmark runner ===" \
    && cat > /benchmark/bench.js << 'EOF'
// Official QuickJS bench-v8 benchmark runner
// Based on the structure found in quickjs-extras

// The official bench-v8 uses a specific pattern
// Let's try to execute it properly

try {
    print("=== QuickJS Official Bench-V8 Benchmark ===");
    
    // Load base.js first (contains utilities)
    try {
        std.load("/benchmark/base.js");
        print("✓ base.js loaded");
    } catch(e) {
        print("Note: base.js load issue: " + e);
    }
    
    // Try to run the combined benchmark
    print("Running combined.js benchmark...");
    std.load("/benchmark/combined.js");
    
} catch(e) {
    print("Benchmark error: " + e);
    print("Stack: " + (e.stack || "no stack"));
    
    // Fallback: run individual tests
    print("\nTrying individual tests...");
    const tests = [
        "crypto.js", "deltablue.js", "earley-boyer.js", 
        "navier-stokes.js", "raytrace.js", "regexp.js", 
        "richards.js", "splay.js"
    ];
    
    for (let i = 0; i < tests.length; i++) {
        try {
            print("Running " + tests[i] + "...");
            std.load("/benchmark/" + tests[i]);
            print("✓ " + tests[i] + " completed");
        } catch(e2) {
            print("✗ " + tests[i] + " failed: " + e2);
        }
    }
}
EOF

# Stage 2: Runtime
FROM busybox:musl

# Copy benchmark files and binary
COPY --from=builder /benchmark/ /benchmark/

# Set working directory
WORKDIR /benchmark

# Run official bench-v8
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
