# 构建阶段
FROM alpine:latest AS builder

RUN set -eux \
    && FILENAME=qjs-libuv \
    && apk add --no-cache --no-scripts --virtual .build-deps \
        build-base \
        curl \
        tar \
        xz \
        binutils \
        pkgconfig \
        libuv-dev \
    # 尝试安装 upx，如果不可用则继续（某些架构可能不支持）
    \
    && apk add --no-cache --no-scripts --virtual .upx-deps \
        upx 2>/dev/null || echo "upx not available, skipping compression" \
    \
    # 下载QuickJS源代码
    && curl -L https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz | tar -xJf - -C /tmp \
    && cd /tmp/quickjs-* \
    \
    # 复制并构建libuv扩展
    && cp /quickjs-libuv.c . && cp /quickjs-libuv.h . \
    \
    # 构建QuickJS核心 + libuv扩展
    && make -j$(nproc) \
    && gcc -g -Wall -O2 -DCONFIG_VERSION=\"2025-09-13\" \
        -I. \
        quickjs.c libregexp.c libunicode.c cutils.c qjs.c quickjs-libuv.c \
        -o $FILENAME \
        -lm -ldl -lpthread $(pkg-config --libs libuv) \
    \
    && strip --strip-all $FILENAME \
    && (upx --best --lzma $FILENAME 2>/dev/null || echo "upx compression skipped") \
    && mv $FILENAME /qjs-libuv-static \
    \
    # 下载额外文件
    && curl -L https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz | tar -xJf - -C /tmp \
    && mkdir /bench \
    && cp -r /tmp/quickjs-*/tests/bench-v8/* /bench/ \
    \
    # 创建示例代码
    && cat > /bench/example-libuv.js << 'EXAMPLE_EOF'
// QuickJS + libuv 示例代码

import * as uv from "libuv";

console.log("=== QuickJS libuv 异步I/O演示 ===\n");

// 1. 异步文件读取示例
async function testFileRead() {
    console.log("1. 测试异步文件读取...");
    try {
        // 创建测试文件
        await uv.fsWrite("/tmp/test.txt", "Hello from QuickJS libuv!");
        console.log("   ✓ 写入测试文件成功");
        
        // 异步读取
        const data = await uv.fsRead("/tmp/test.txt");
        console.log("   ✓ 读取内容:", new TextDecoder().decode(data));
    } catch (err) {
        console.error("   ✗ 文件操作失败:", err.message);
    }
}

// 2. 定时器示例
function testTimers() {
    console.log("\n2. 测试定时器...");
    
    uv.setTimeout(() => {
        console.log("   ✓ 1秒后执行的定时器");
    }, 1000);
    
    uv.setTimeout(() => {
        console.log("   ✓ 2秒后执行的定时器");
    }, 2000);
}

// 3. TCP服务器示例
function testTCPServer() {
    console.log("\n3. 测试TCP服务器...");
    
    const server = uv.createTCPServer(8080, (conn) => {
        if (conn.type === "connection") {
            console.log("   ✓ 收到TCP连接");
        }
    });
    
    console.log("   ✓ TCP服务器启动在端口 8080");
    console.log("   (服务器将在事件循环中运行)");
    
    // 5秒后停止服务器
    uv.setTimeout(() => {
        console.log("   ✓ 5秒后停止服务器");
        uv.stop();
    }, 5000);
}

// 主函数
async function main() {
    await testFileRead();
    testTimers();
    testTCPServer();
    
    console.log("\n=== 启动事件循环 ===");
    console.log("按 Ctrl+C 退出\n");
    
    // 启动事件循环
    uv.run();
}

// 执行
main().catch(console.error);
EXAMPLE_EOF

# 运行阶段 - 包含libuv的最小化镜像
FROM alpine:latest

# 安装libuv运行时库
RUN apk add --no-cache libuv

COPY --from=builder /qjs-libuv-static /qjs
COPY --from=builder /bench/ /bench/

WORKDIR /bench

ENTRYPOINT ["/qjs", "example-libuv.js"]
