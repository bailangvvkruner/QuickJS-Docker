# QuickJS Docker Image - Official Bench-V8 Benchmark
FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache make gcc musl-dev curl tar xz binutils upx

# Download QuickJS source and extras
RUN curl -L -o /tmp/quickjs.tar.xz https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz && \
    tar -xf /tmp/quickjs.tar.xz -C /tmp/ && mv /tmp/quickjs-* /tmp/quickjs && \
    curl -L -o /tmp/quickjs-extras.tar.xz https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz && \
    tar -xf /tmp/quickjs-extras.tar.xz -C /tmp/

# Extract bench-v8 files
RUN mkdir -p /benchmark && \
    cp -r /tmp/quickjs-2025-09-13/tests/bench-v8/* /benchmark/

# Build QuickJS
RUN cd /tmp/quickjs && \
    make -j$(nproc) && \
    make qjs LDFLAGS="-static" && \
    mv qjs /benchmark/qjs-static && \
    strip --strip-all /benchmark/qjs-static && \
    upx --best /benchmark/qjs-static

# Create simple benchmark runner
RUN cat > /benchmark/bench.js << 'EOF'
print("QuickJS Bench-V8 Benchmark");
print("Loading tests...");
try {
    std.load("/benchmark/combined.js");
} catch(e) {
    print("Error: " + e);
}
print("Done");
EOF

# Stage 2
FROM busybox:musl
COPY --from=builder /benchmark/ /benchmark/
WORKDIR /benchmark
ENTRYPOINT ["/benchmark/qjs-static", "bench.js"]
