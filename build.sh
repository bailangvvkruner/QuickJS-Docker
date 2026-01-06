#!/bin/bash

# QuickJS + libuv 构建脚本
set -e

echo "=== QuickJS + libuv 构建脚本 ==="

# 检查系统依赖
if ! command -v gcc &> /dev/null; then
    echo "错误: 未找到gcc编译器"
    exit 1
fi

if ! command -v make &> /dev/null; then
    echo "错误: 未找到make工具"
    exit 1
fi

# 检查libuv
if ! pkg-config --exists libuv; then
    echo "错误: 未找到libuv库"
    echo "请安装libuv开发包:"
    echo "  Ubuntu/Debian: sudo apt-get install libuv1-dev"
    echo "  CentOS/RHEL: sudo yum install libuv-devel"
    echo "  macOS: brew install libuv"
    exit 1
fi

# 获取QuickJS源代码
QUICKJS_VERSION="2025-09-13-2"
QUICKJS_DIR="quickjs-${QUICKJS_VERSION}"
QUICKJS_TAR="quickjs-${QUICKJS_VERSION}.tar.xz"

if [ ! -d "${QUICKJS_DIR}" ]; then
    echo "下载QuickJS源代码..."
    if [ ! -f "${QUICKJS_TAR}" ]; then
        curl -L "https://bellard.org/quickjs/${QUICKJS_TAR}" -o "${QUICKJS_TAR}"
    fi
    tar -xJf "${QUICKJS_TAR}"
fi

# 复制libuv绑定文件
echo "复制libuv绑定文件..."
cp quickjs-libuv.c quickjs-libuv.h "${QUICKJS_DIR}/"

# 修改QuickJS的Makefile，添加libuv支持
echo "修改构建配置..."

cd "${QUICKJS_DIR}"

# 创建扩展的Makefile
cat > Makefile.libuv << 'EOF'
# QuickJS + libuv 扩展构建

CC = gcc
CFLAGS = -g -Wall -O2 -D_GNU_SOURCE -DCONFIG_VERSION=\"2025-09-13\"
LDFLAGS = -lm -ldl -lpthread
LIBUV_CFLAGS = $(shell pkg-config --cflags libuv)
LIBUV_LIBS = $(shell pkg-config --libs libuv)

# QuickJS 核心文件
QUICKJS_OBJS = quickjs.o libregexp.o libunicode.o cutils.o qjs.o
LIBQUICKJS_OBJS = quickjs.o libregexp.o libunicode.o cutils.o

# libuv 扩展
LIBUV_OBJS = quickjs-libuv.o

# 目标
all: qjs-libuv

# 编译QuickJS核心
quickjs.o: quickjs.c quickjs.h
	$(CC) $(CFLAGS) $(LIBUV_CFLAGS) -c -o $@ $<

libregexp.o: libregexp.c libregexp.h
	$(CC) $(CFLAGS) -c -o $@ $<

libunicode.o: libunicode.c libunicode.h
	$(CC) $(CFLAGS) -c -o $@ $<

cutils.o: cutils.c cutils.h
	$(CC) $(CFLAGS) -c -o $@ $<

qjs.o: qjs.c quickjs.h
	$(CC) $(CFLAGS) $(LIBUV_CFLAGS) -c -o $@ $<

# 编译libuv扩展
quickjs-libuv.o: quickjs-libuv.c quickjs-libuv.h quickjs.h
	$(CC) $(CFLAGS) $(LIBUV_CFLAGS) -c -o $@ $<

# 链接主程序
qjs-libuv: $(QUICKJS_OBJS) $(LIBUV_OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(LIBUV_LIBS)

# 静态库
libquickjs.a: $(LIBQUICKJS_OBJS)
	ar rcs $@ $^

libquickjs-libuv.a: $(LIBQUICKJS_OBJS) $(LIBUV_OBJS)
	ar rcs $@ $^

# 清理
clean:
	rm -f *.o qjs-libuv libquickjs.a libquickjs-libuv.a

.PHONY: all clean
EOF

# 构建
echo "开始构建..."
make -f Makefile.libuv

# 复制输出
cd ..
cp "${QUICKJS_DIR}/qjs-libuv" ./

echo "构建完成!"
echo "生成的可执行文件: ./qjs-libuv"
echo ""
echo "测试libuv功能:"
echo "  ./qjs-libuv -e 'import * as uv from \"libuv\"; console.log(\"libuv模块加载成功\");'"