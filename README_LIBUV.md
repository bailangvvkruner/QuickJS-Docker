# QuickJS + libuv 异步I/O集成

> 为QuickJS JavaScript引擎添加libuv支持，实现类似Node.js的异步I/O功能

## 🚀 项目概述

这个项目将libuv事件循环集成到QuickJS中，提供了以下核心功能：

- ✅ **异步文件系统操作** (fsRead, fsWrite)
- ✅ **事件循环控制** (run, stop)
- ✅ **定时器** (setTimeout)
- ✅ **TCP网络** (createTCPServer)
- ✅ **Promise支持** (完全异步API)

## 📁 项目文件

```
.
├── quickjs-libuv-v2.c      # 核心libuv绑定实现
├── quickjs-libuv.h         # 头文件
├── build-libuv.sh          # 一键构建脚本
├── Dockerfile              # Docker构建配置
├── example-async-demo.js   # 演示代码（模拟）
├── test-libuv.js           # 测试代码（模拟）
├── test-libuv-module.js    # 实际测试模块（构建时生成）
├── LIBUV_INTEGRATION.md    # 详细文档
└── README_LIBUV.md         # 本文件
```

## ⚡ 快速开始

### 1. 系统要求

- GCC编译器
- Make工具
- libuv开发库
- pkg-config

### 2. 安装依赖

**Ubuntu/Debian:**
```bash
sudo apt-get install build-base curl tar xz binutils pkg-config libuv1-dev
```

**CentOS/RHEL:**
```bash
sudo yum install gcc make curl tar xz binutils pkgconfig libuv-devel
```

**macOS:**
```bash
brew install pkg-config libuv
```

### 3. 构建项目

```bash
# 给脚本执行权限
chmod +x build-libuv.sh

# 一键构建
./build-libuv.sh
```

### 4. 运行测试

```bash
# 运行测试模块
./qjs-libuv test-libuv-module.js
```

## 📝 API使用示例

### 异步文件读取

```javascript
import * as uv from "libuv";

async function readFile() {
    try {
        const data = await uv.fsRead("/tmp/example.txt");
        const content = new TextDecoder().decode(data);
        console.log("文件内容:", content);
    } catch (err) {
        console.error("读取失败:", err.message);
    }
}
```

### 异步文件写入

```javascript
import * as uv from "libuv";

async function writeFile() {
    try {
        const bytesWritten = await uv.fsWrite("/tmp/example.txt", "Hello World!");
        console.log(`写入了 ${bytesWritten} 字节`);
    } catch (err) {
        console.error("写入失败:", err.message);
    }
}
```

### 定时器

```javascript
import * as uv from "libuv";

uv.setTimeout(() => {
    console.log("1秒后执行");
}, 1000);

uv.setTimeout(() => {
    console.log("2秒后执行");
    uv.stop(); // 停止事件循环
}, 2000);

uv.run(); // 启动事件循环
```

### TCP服务器

```javascript
import * as uv from "libuv";

const server = uv.createTCPServer(8080, (conn) => {
    if (conn.type === "connection") {
        console.log("新连接来自:", conn.from);
    }
});

uv.run(); // 处理连接
```

### 并发操作

```javascript
import * as uv from "libuv";

async function concurrentOps() {
    const results = await Promise.all([
        uv.fsWrite("/tmp/file1.txt", "数据1"),
        uv.fsWrite("/tmp/file2.txt", "数据2"),
        uv.fsRead("/tmp/example.txt")
    ]);
    
    console.log("所有操作完成:", results);
}
```

## 🏗️ 架构说明

```
┌─────────────────────────────────────┐
│      QuickJS JavaScript 环境         │
│  (import * as uv from "libuv")      │
├─────────────────────────────────────┤
│   libuv 绑定层 (quickjs-libuv-v2.c) │
│  - JSUVContext                      │
│  - JSUVFSRequest                    │
│  - JSUVTCPServer                    │
│  - JSUVTimer                        │
├─────────────────────────────────────┤
│        libuv 事件循环                │
│  - uv_run()                         │
│  - uv_fs_*()                        │
│  - uv_tcp_*()                       │
│  - uv_timer_*()                     │
├─────────────────────────────────────┤
│      操作系统I/O子系统               │
│  - 文件系统                         │
│  - 网络栈                           │
│  - 定时器                           │
└─────────────────────────────────────┘
```

## 🔧 核心组件

### 1. JSUVContext
管理QuickJS上下文和libuv循环的生命周期

### 2. JSUVFSRequest
处理异步文件系统操作，自动管理内存和Promise

### 3. JSUVTCPServer
TCP服务器实现，处理连接事件

### 4. JSUVTimer
定时器管理，支持一次性定时器

## 🎯 功能特性

### 已实现
- ✅ 异步文件读取 (fsRead)
- ✅ 异步文件写入 (fsWrite)
- ✅ 事件循环控制 (run/stop)
- ✅ 定时器 (setTimeout)
- ✅ TCP服务器 (createTCPServer)
- ✅ Promise支持
- ✅ 错误处理
- ✅ 并发操作支持

### 未来扩展
- 🔄 UDP支持
- 🔄 子进程管理
- 🔄 DNS解析
- 🔄 更多文件系统操作
- 🔄 HTTP服务器
- 🔄 WebSocket支持

## 🐛 故障排除

### 常见问题

**Q: 编译时找不到libuv**
```bash
# 确保安装了开发包
sudo apt-get install libuv1-dev  # Ubuntu
sudo yum install libuv-devel     # CentOS
```

**Q: 运行时模块加载失败**
```bash
# 检查QuickJS是否正确编译
./qjs-libuv -e 'console.log("QuickJS工作正常")'
```

**Q: 事件循环不工作**
```javascript
// 确保调用了uv.run()
uv.setTimeout(() => console.log("定时器"), 1000);
uv.run(); // 必须调用！
```

## 📊 性能特点

1. **非阻塞I/O**: 所有操作异步执行，不阻塞主线程
2. **事件驱动**: 单线程处理大量并发连接
3. **内存高效**: QuickJS的轻量级设计 + libuv的高效实现
4. **快速启动**: QuickJS启动时间极短

## 🔍 技术细节

### 内存管理
- 使用QuickJS的引用计数
- libuv句柄的正确清理
- Promise的自动垃圾回收

### 线程模型
- 单线程事件循环
- 所有回调在主线程执行
- 无需担心并发问题

### 错误处理
- 统一的错误格式
- Promise自动拒绝
- 详细的错误信息

## 📚 更多资源

- [详细API文档](LIBUV_INTEGRATION.md)
- [QuickJS官方文档](https://bellard.org/quickjs/)
- [libuv官方文档](https://docs.libuv.org/)

## 🤝 贡献

欢迎提交Issue和Pull Request！

## 📄 许可证

MIT License - 基于QuickJS的许可

---

**构建时间**: 2026-01-06  
**版本**: 1.0.0  
**状态**: ✅ 完整实现