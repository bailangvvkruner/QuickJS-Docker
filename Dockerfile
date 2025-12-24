# QuickJS Docker Image with bench-v8 benchmark
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
    python3 \
    py3-pip \
    nodejs \
    npm \
    perl \
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
    && mv /tmp/quickjs-extras-* /tmp/quickjs-extras

# Build QuickJS and create static qjs interpreter
RUN set -eux \
    && cd /tmp/quickjs \
    && echo "=== Building QuickJS ===" \
    && make -j$(nproc) \
    && make install \
    \
    && echo "=== Testing QuickJS installation ===" \
    && qjs --version \
    && qjsc --version \
    \
    && echo "=== Creating static qjs interpreter ===" \
    && mkdir -p /benchmark

# Prepare bench-v8 benchmark and compile qjs as static binary
RUN set -eux \
    && echo "=== Setting up bench-v8 benchmark ===" \
    && mkdir -p /benchmark \
    && cp -r /tmp/quickjs-extras/bench-v8 /benchmark/ \
    \
    && echo "=== Compiling qjs as static binary ===" \
    && cd /tmp/quickjs \
    # Create a simple C wrapper that calls qjs_main
    && cat > /tmp/static_qjs.c << 'EOF'
#include "quickjs-libc.h"

int main(int argc, char **argv) {
    return qjs_main(argc, argv);
}
EOF
    # Compile qjs as static binary using the static library
    && gcc -static -o /benchmark/qjs-static \
       /tmp/static_qjs.c \
       libquickjs.a \
       -lm -ldl -lpthread \
    \
    && echo "=== Verifying static qjs binary ===" \
    && file /benchmark/qjs-static \
    \
    && echo "=== Copying dynamic qjs for comparison ===" \
    && cp /tmp/quickjs/qjs /benchmark/ \
    && cp /tmp/quickjs/qjsc /benchmark/

# Create a script to run bench-v8 with static qjs interpreter
RUN set -eux \
    && echo "=== Creating benchmark runner script ===" \
    && cat > /benchmark/run-benchmark.sh << 'EOF'
#!/bin/sh

echo "=== QuickJS Static Interpreter Test ==="
echo ""

echo "=== Dynamic qjs Interpreter ==="
echo "File type:"
file /benchmark/qjs
echo "Version:"
/benchmark/qjs --version
echo ""

echo "=== Static qjs Interpreter ==="
echo "File type:"
file /benchmark/qjs-static
echo "Version:"
/benchmark/qjs-static --version
echo ""

echo "=== Running bench-v8 benchmark with dynamic qjs ==="
cd /benchmark/bench-v8
if [ -f "bench.js" ]; then
    echo "Running bench.js with dynamic qjs interpreter..."
    /benchmark/qjs bench.js
else
    echo "ERROR: bench.js not found in /benchmark/bench-v8/"
    ls -la
fi

echo ""
echo "=== Running bench-v8 benchmark with static qjs ==="
echo "Running bench.js with static qjs interpreter..."
cd /benchmark/bench-v8
/benchmark/qjs-static bench.js

echo ""
echo "=== Benchmark completed ==="
echo "Summary:"
echo "- Dynamic interpreter: /benchmark/qjs (requires system libraries)"
echo "- Static interpreter: /benchmark/qjs-static (standalone, no dependencies)"
echo ""
echo "The static qjs interpreter can run any JavaScript file independently."
echo "Example usage on another system:"
echo "  /path/to/qjs-static /path/to/script.js"
EOF
    && chmod +x /benchmark/run-benchmark.sh

# Strip binaries for smaller size
RUN set -eux \
    && echo "=== Stripping binaries ===" \
    && strip -v --strip-all /benchmark/qjs \
    && strip -v --strip-all /benchmark/qjsc \
    && strip -v --strip-all /benchmark/qjs-static \
    && upx --best --lzma /benchmark/qjs \
    && upx --best --lzma /benchmark/qjsc \
    && upx --best --lzma /benchmark/qjs-static

# Stage 2: Final Runtime (Minimal)
# FROM alpine:latest
# FROM scratch
FROM busybox:musl

# Copy only the essential files for running the benchmark
COPY --from=builder /benchmark /benchmark

# Copy required dynamic loader for the stripped static binary (if any)
# For a truly static binary, this may not be needed, but we ensure compatibility
COPY --from=builder /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1

# Set working directory
WORKDIR /benchmark/bench-v8

# Set entrypoint to run the benchmark using the static qjs interpreter
# We override the script to focus only on static binary execution
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
