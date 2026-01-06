# QuickJS + libuv 异步I/O集成指南

这个项目为QuickJS JavaScript引擎添加了libuv集成，实现了类似Node.js的异步I/O功能。

## 功能特性

### ✅ 已实现的功能

1. **异步文件系统操作**
   - `uv.fsRead(filename)` - 异步读取文件
   - `uv.fsWrite(filename, data)` - 异步写入文件

2. **事件循环控制**
   - `uv.run()` - 启动libuv事件循环
   - `uv.stop()` - 停止事件循环

3. **定时器**
   - `uv.setTimeout(callback, delay)` - 异步定时器

4. **TCP网络**
   - `uv.createTCPServer(port, callback)` - 创建TCP服务器

### 🔧 技术架构

```
┌─────────────────────────────────────┐
│      QuickJS JavaScript 环境         │
├─────────────────────────────────────┤
│   libuv 绑定层 (quickjs-libuv.c)    │
├─────────────────────────────────────┤
│        libuv 事件循环                │
├─────────────────────────────────────┤
│      操作系统I/O子系统               │
└─────────────────────────────────────┘
```

## 快速开始

### 方法1: 使用Docker构建

```bash
# 构建镜像
docker build -t quickjs-libuv .

# 运行示例
docker run --rm quickjs-libuv
```

### 方法2: 本地构建

#### 系统要求

- GCC编译器
- Make工具
- libuv开发库
- pkg-config

#### 安装依赖

**Ubuntu/Debian:**
```bash
sudo apt-get update
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

#### 构建步骤

```bash
# 1. 克隆或下载项目文件
# 2. 给构建脚本执行权限
chmod +x build.sh

# 3. 运行构建脚本
./build.sh

# 4. 测试构建结果
./qjs-libuv -e 'import * as uv from "libuv"; console.log("libuv模块加载成功");'
```

## API参考

### 文件系统操作

#### `uv.fsRead(filename)`

异步读取文件内容。

**参数:**
- `filename` (string): 文件路径

**返回:** Promise<Uint8Array>

**示例:**
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

#### `uv.fsWrite(filename, data)`

异步写入文件。

**参数:**
- `filename` (string): 文件路径
- `data` (string | Uint8Array): 要写入的数据

**返回:** Promise<number> - 写入的字节数

**示例:**
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

### 事件循环

#### `uv.run()`

启动libuv事件循环，处理所有挂起的异步操作。

**返回:** Promise<number>

**示例:**
```javascript
import * as uv from "libuv";

// 设置定时器
uv.setTimeout(() => {
    console.log("1秒后执行");
}, 1000);

// 启动事件循环
await uv.run();
```

#### `uv.stop()`

停止事件循环。

**示例:**
```javascript
import * as uv from "libuv";

uv.setTimeout(() => {
    console.log("5秒后停止");
    uv.stop();
}, 5000);

uv.run();
```

### 定时器

#### `uv.setTimeout(callback, delay)`

设置一次性定时器。

**参数:**
- `callback` (Function): 回调函数
- `delay` (number): 延迟时间（毫秒）

**返回:** number - 定时器ID

**示例:**
```javascript
import * as uv from "libuv";

const timerId = uv.setTimeout(() => {
    console.log("定时器触发");
}, 1000);

// 可以存储timerId用于取消（未来扩展）
```

### 网络操作

#### `uv.createTCPServer(port, callback)`

创建TCP服务器。

**参数:**
- `port` (number): 监听端口
- `callback` (Function): 连接回调函数

**返回:** Object - 服务器对象，包含close()方法

**示例:**
```javascript
import * as uv from "libuv";

const server = uv.createTCPServer(8080, (connection) => {
    if (connection.type === "connection") {
        console.log("新连接来自:", connection.from);
    }
});

// 启动事件循环处理连接
uv.run();
```

## 完整示例

### 异步文件处理

```javascript
import * as uv from "libuv";

async function processFiles() {
    console.log("开始处理文件...");
    
    // 写入数据
    await uv.fsWrite("/tmp/data.txt", "重要数据");
    
    // 读取数据
    const data = await uv.fsRead("/tmp/data.txt");
    const content = new TextDecoder().decode(data);
    
    console.log("处理完成:", content);
}

processFiles().catch(console.error);
```

### 多任务并发

```javascript
import * as uv from "libuv";

async function concurrentTasks() {
    // 并发执行多个文件操作
    const tasks = [
        uv.fsWrite("/tmp/file1.txt", "文件1"),
        uv.fsWrite("/tmp/file2.txt", "文件2"),
        uv.fsWrite("/tmp/file3.txt", "文件3"),
    ];
    
    const results = await Promise.all(tasks);
    console.log("所有任务完成:", results);
}

concurrentTasks().catch(console.error);
```

### 简单的TCP服务器

```javascript
import * as uv from "libuv";

// 创建TCP服务器
const server = uv.createTCPServer(9000, (conn) => {
    if (conn.type === "connection") {
        console.log(`客户端连接: ${conn.from}`);
    }
});

// 设置5秒后自动关闭
uv.setTimeout(() => {
    console.log("服务器运行5秒后关闭");
    server.close();
    uv.stop();
}, 5000);

console.log("TCP服务器启动在端口 9000");
uv.run();
```

## 高级用法

### 错误处理

```javascript
import * as uv from "libuv";

async function robustOperation() {
    try {
        const data = await uv.fsRead("/nonexistent/file.txt");
    } catch (err) {
        console.error("操作失败:", err.message);
        // 处理错误
    }
}
```

### Promise链

```javascript
import * as uv from "libuv";

uv.fsWrite("/tmp/step1.txt", "第一步")
    .then(() => uv.fsWrite("/tmp/step2.txt", "第二步"))
    .then(() => uv.fsWrite("/tmp/step3.txt", "第三步"))
    .then(() => console.log("所有步骤完成"))
    .catch(err => console.error("出错:", err));
```

## 架构说明

### 核心组件

1. **JSUVContext**: 管理QuickJS上下文和libuv循环
2. **JSUVFSRequest**: 文件系统异步请求结构
3. **JSUVTCPServer**: TCP服务器结构

### 事件循环集成

```
QuickJS调用 → libuv绑定 → libuv事件循环 → 操作系统I/O → 回调Promise
```

### 内存管理

- 使用QuickJS的引用计数
- libuv句柄的正确清理
- Promise的自动垃圾回收

## 性能考虑

1. **异步优势**: 非阻塞I/O提高并发性能
2. **事件循环**: 单线程处理大量并发连接
3. **内存效率**: QuickJS的轻量级特性

## 限制和注意事项

1. **单线程**: 所有操作在单线程中执行
2. **错误处理**: 需要适当的Promise错误处理
3. **资源清理**: 注意及时关闭文件和网络连接
4. **平台差异**: 某些系统调用可能因平台而异

## 扩展建议

未来可以添加的功能：

- [ ] 更多的文件系统操作（删除、重命名、统计等）
- [ ] UDP支持
- [ ] 子进程管理
- [ ] DNS解析
- [ ] 加密操作
- [ ] HTTP服务器

## 故障排除

### 常见问题

**Q: libuv模块无法加载**
A: 确保libuv已正确安装，并且QuickJS在编译时包含了libuv扩展

**Q: 事件循环不工作**
A: 检查是否有未完成的异步操作，确保调用了`uv.run()`

**Q: 文件操作失败**
A: 检查文件权限和路径是否正确

### 调试技巧

```javascript
// 添加详细日志
console.log("状态:", {
    hasLoop: uv.run !== undefined,
    hasFS: uv.fsRead !== undefined,
    hasNetwork: uv.createTCPServer !== undefined
});
```

## 许可证

基于QuickJS的MIT许可证。

## 贡献

欢迎提交Issue和Pull Request来改进这个集成。

---

**作者**: QuickJS + libuv 集成项目  
**版本**: 1.0.0  
**最后更新**: 2026-01-06