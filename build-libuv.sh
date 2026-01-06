#!/bin/bash

# QuickJS + libuv 简化构建脚本
set -e

echo "=== QuickJS + libuv 构建脚本 ==="

# 检查依赖
check_deps() {
    echo "检查系统依赖..."
    
    if ! command -v gcc &> /dev/null; then
        echo "❌ 未找到gcc"
        return 1
    fi
    
    if ! command -v make &> /dev/null; then
        echo "❌ 未找到make"
        return 1
    fi
    
    if ! command -v pkg-config &> /dev/null; then
        echo "❌ 未找到pkg-config"
        return 1
    fi
    
    if ! pkg-config --exists libuv; then
        echo "❌ 未找到libuv库"
        echo "请安装:"
        echo "  Ubuntu: sudo apt-get install libuv1-dev"
        echo "  CentOS: sudo yum install libuv-devel"
        echo "  macOS: brew install libuv"
        return 1
    fi
    
    echo "✓ 所有依赖已满足"
    return 0
}

# 下载QuickJS
download_quickjs() {
    local version="2025-09-13-2"
    local tarfile="quickjs-${version}.tar.xz"
    local dir="quickjs-${version}"
    
    if [ -d "$dir" ]; then
        echo "✓ QuickJS源码已存在"
        return 0
    fi
    
    echo "下载QuickJS ${version}..."
    if [ ! -f "$tarfile" ]; then
        curl -L "https://bellard.org/quickjs/${tarfile}" -o "$tarfile" || {
            echo "❌ 下载失败"
            return 1
        }
    fi
    
    echo "解压QuickJS..."
    tar -xJf "$tarfile" || {
        echo "❌ 解压失败"
        return 1
    }
    
    echo "✓ QuickJS下载完成"
    return 0
}

# 构建QuickJS + libuv
build_quickjs_libuv() {
    local dir="quickjs-2025-09-13-2"
    
    if [ ! -d "$dir" ]; then
        echo "❌ QuickJS目录不存在"
        return 1
    fi
    
    echo "构建QuickJS + libuv..."
    
    cd "$dir"
    
    # 获取libuv配置
    LIBUV_CFLAGS=$(pkg-config --cflags libuv)
    LIBUV_LIBS=$(pkg-config --libs libuv)
    
    echo "libuv配置: $LIBUV_CFLAGS $LIBUV_LIBS"
    
    # 首先构建QuickJS核心
    if [ ! -f "quickjs.o" ]; then
        echo "编译QuickJS核心..."
        gcc -g -Wall -O2 -DCONFIG_VERSION=\"2025-09-13\" \
            -c quickjs.c -o quickjs.o
    fi
    
    if [ ! -f "libregexp.o" ]; then
        gcc -g -Wall -O2 -c libregexp.c -o libregexp.o
    fi
    
    if [ ! -f "libunicode.o" ]; then
        gcc -g -Wall -O2 -c libunicode.c -o libunicode.o
    fi
    
    if [ ! -f "cutils.o" ]; then
        gcc -g -Wall -O2 -c cutils.c -o cutils.o
    fi
    
    if [ ! -f "qjs.o" ]; then
        gcc -g -Wall -O2 -DCONFIG_VERSION=\"2025-09-13\" -I. \
            -c qjs.c -o qjs.o
    fi
    
    # 编译libuv扩展
    echo "编译libuv扩展..."
    gcc -g -Wall -O2 -DCONFIG_VERSION=\"2025-09-13\" -I. \
        $LIBUV_CFLAGS \
        -c ../quickjs-libuv-v2.c -o quickjs-libuv.o
    
    # 链接最终程序
    echo "链接程序..."
    gcc -g -Wall -O2 -o qjs-libuv \
        quickjs.o libregexp.o libunicode.o cutils.o qjs.o quickjs-libuv.o \
        -lm -ldl -lpthread $LIBUV_LIBS
    
    # 复制到上级目录
    cp qjs-libuv ../
    
    cd ..
    
    echo "✓ 构建完成: ./qjs-libuv"
    return 0
}

# 创建测试模块
create_test_module() {
    cat > test-libuv-module.js << 'EOF'
// libuv模块测试
import * as uv from "libuv";

console.log("=== QuickJS libuv 模块测试 ===\n");

async function main() {
    // 测试文件操作
    console.log("1. 文件操作测试");
    try {
        const writeResult = await uv.fsWrite("/tmp/quickjs-test.txt", "Hello from QuickJS!");
        console.log("   ✓ 写入:", writeResult, "字节");
        
        const data = await uv.fsRead("/tmp/quickjs-test.txt");
        const content = new TextDecoder().decode(data);
        console.log("   ✓ 读取:", content);
    } catch (err) {
        console.log("   ✗ 错误:", err.message);
    }
    
    // 测试定时器
    console.log("\n2. 定时器测试");
    await new Promise((resolve) => {
        uv.setTimeout(() => {
            console.log("   ✓ 500ms 定时器触发");
            resolve();
        }, 500);
    });
    
    // 测试并发
    console.log("\n3. 并发测试");
    const start = Date.now();
    await Promise.all([
        uv.fsWrite("/tmp/file1.txt", "A"),
        uv.fsWrite("/tmp/file2.txt", "B"),
        uv.fsWrite("/tmp/file3.txt", "C")
    ]);
    console.log("   ✓ 并发完成，耗时:", Date.now() - start, "ms");
    
    console.log("\n✅ 所有测试完成!");
}

main().catch(console.error);
EOF
    echo "✓ 测试模块已创建: test-libuv-module.js"
}

# 显示使用说明
show_usage() {
    echo ""
    echo "使用方法:"
    echo "  1. 构建: ./build-libuv.sh"
    echo "  2. 测试: ./qjs-libuv test-libuv-module.js"
    echo "  3. 交互: ./qjs-libuv"
    echo ""
    echo "可用功能:"
    echo "  - uv.fsRead(filename)     异步读取文件"
    echo "  - uv.fsWrite(filename, data) 异步写入文件"
    echo "  - uv.setTimeout(callback, delay) 定时器"
    echo "  - uv.createTCPServer(port, callback) TCP服务器"
    echo "  - uv.run()                启动事件循环"
    echo "  - uv.stop()               停止事件循环"
    echo ""
}

# 主函数
main() {
    check_deps || exit 1
    download_quickjs || exit 1
    build_quickjs_libuv || exit 1
    create_test_module
    show_usage
    
    echo "🎉 构建成功!"
    echo "运行测试: ./qjs-libuv test-libuv-module.js"
}

# 执行
main