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

# Build QuickJS
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    \
    && echo "=== Creating static qjs ===" \
    && make qjs LDFLAGS="-static" \
    && mv qjs /benchmark/qjs-static

# Create proper bench.js wrapper for official benchmark
RUN set -eux \
    && echo "=== Creating official benchmark runner ===" \
    && cat > /benchmark/bench.js << 'EOF'
#!/usr/bin/env qjs
// Official QuickJS bench-v8 benchmark runner
// This runs the authentic V8 benchmark suite

// Load the benchmark harness
try {
    // Load base.js first
    std.load("/benchmark/base.js");
    
    // Define Run function that the benchmark expects
    if (typeof Run === 'undefined') {
        // The benchmark calls Run() which should execute the tests
        // Based on the official bench-v8 structure
        print("QuickJS bench-v8 benchmark");
        print("Running combined.js...");
        
        // Execute the combined benchmark
        std.load("/benchmark/combined.js");
    }
} catch(e) {
    print("Error: " + e);
    print("Stack: " + e.stack);
}
EOF

# Make executable
RUN chmod +x /benchmark/bench.js

# Stage 2: Runtime
FROM busybox:musl

# Copy benchmark files and binary
COPY --from=builder /benchmark/ /benchmark/

# Set working directory
WORKDIR /benchmark

# Run official bench-v8
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
