/**
 * QuickJS + libuv 异步I/O演示
 * 演示类似Node.js的异步功能
 */

// 模拟导入libuv模块（在实际环境中会从QuickJS扩展加载）
// 这里我们创建一个模拟版本用于演示概念

class LibUVMock {
    constructor() {
        this.callbacks = [];
        this.timerId = 0;
    }

    // 异步文件读取
    async fsRead(filename) {
        console.log(`[FS] 开始异步读取文件: ${filename}`);
        
        return new Promise((resolve, reject) => {
            // 模拟异步操作
            setTimeout(() => {
                try {
                    // 模拟文件内容
                    const content = `这是来自 ${filename} 的异步文件内容\n`;
                    const buffer = new TextEncoder().encode(content);
                    console.log(`[FS] 完成读取: ${filename}`);
                    resolve(buffer);
                } catch (err) {
                    reject(err);
                }
            }, 100); // 模拟100ms延迟
        });
    }

    // 异步文件写入
    async fsWrite(filename, data) {
        console.log(`[FS] 开始异步写入文件: ${filename}`);
        
        return new Promise((resolve, reject) => {
            setTimeout(() => {
                try {
                    const content = typeof data === 'string' ? data : new TextDecoder().decode(data);
                    console.log(`[FS] 完成写入: ${filename}, 内容: ${content}`);
                    resolve(content.length);
                } catch (err) {
                    reject(err);
                }
            }, 80); // 模拟80ms延迟
        });
    }

    // 设置超时
    setTimeout(callback, delay) {
        const id = ++this.timerId;
        console.log(`[TIMER] 设置定时器 ${id}: ${delay}ms`);
        
        setTimeout(() => {
            console.log(`[TIMER] 触发定时器 ${id}`);
            callback();
        }, delay);
        
        return id;
    }

    // 创建TCP服务器（模拟）
    createTCPServer(port, callback) {
        console.log(`[TCP] 创建服务器，监听端口: ${port}`);
        
        // 模拟连接事件
        setTimeout(() => {
            console.log(`[TCP] 收到连接请求`);
            callback({ type: 'connection', from: '127.0.0.1:12345' });
        }, 500);

        setTimeout(() => {
            console.log(`[TCP] 收到连接请求`);
            callback({ type: 'connection', from: '192.168.1.100:54321' });
        }, 1500);

        return {
            port: port,
            close: () => {
                console.log(`[TCP] 服务器关闭`);
            }
        };
    }

    // 运行事件循环（模拟）
    run() {
        console.log(`[EVENT] 启动事件循环`);
        return new Promise((resolve) => {
            // 模拟事件循环运行
            setTimeout(() => {
                console.log(`[EVENT] 事件循环完成`);
                resolve(0);
            }, 3000);
        });
    }

    // 停止事件循环
    stop() {
        console.log(`[EVENT] 停止事件循环`);
    }
}

// 创建全局实例
const uv = new LibUVMock();

// 演示1: 异步文件操作
async function demoFileOperations() {
    console.log('\n=== 演示1: 异步文件操作 ===\n');
    
    try {
        // 写入文件
        const bytesWritten = await uv.fsWrite('/tmp/demo.txt', 'Hello QuickJS + libuv!');
        console.log(`写入字节数: ${bytesWritten}`);
        
        // 读取文件
        const data = await uv.fsRead('/tmp/demo.txt');
        const content = new TextDecoder().decode(data);
        console.log(`读取内容: ${content.trim()}`);
        
    } catch (err) {
        console.error('文件操作失败:', err);
    }
}

// 演示2: 定时器链
function demoTimers() {
    console.log('\n=== 演示2: 定时器链 ===\n');
    
    return new Promise((resolve) => {
        uv.setTimeout(() => {
            console.log('步骤 1: 500ms 后执行');
            
            uv.setTimeout(() => {
                console.log('步骤 2: 又过了 300ms');
                
                uv.setTimeout(() => {
                    console.log('步骤 3: 最后 200ms');
                    resolve();
                }, 200);
            }, 300);
        }, 500);
    });
}

// 演示3: TCP服务器 + 定时器
function demoTCPServer() {
    console.log('\n=== 演示3: TCP服务器 + 定时器 ===\n');
    
    return new Promise((resolve) => {
        // 创建TCP服务器
        const server = uv.createTCPServer(8080, (conn) => {
            if (conn.type === 'connection') {
                console.log(`新连接: ${conn.from}`);
            }
        });
        
        // 设置停止定时器
        uv.setTimeout(() => {
            console.log('演示完成，停止服务器');
            server.close();
            uv.stop();
            resolve();
        }, 2500);
        
        // 启动事件循环
        uv.run();
    });
}

// 演示4: 并发操作
async function demoConcurrency() {
    console.log('\n=== 演示4: 并发操作 ===\n');
    
    const startTime = Date.now();
    
    // 并发执行多个文件操作
    const promises = [
        uv.fsWrite('/tmp/file1.txt', 'File 1'),
        uv.fsWrite('/tmp/file2.txt', 'File 2'),
        uv.fsWrite('/tmp/file3.txt', 'File 3'),
        uv.fsRead('/tmp/demo.txt')
    ];
    
    const results = await Promise.all(promises);
    
    const endTime = Date.now();
    console.log(`并发操作完成，耗时: ${endTime - startTime}ms`);
    console.log('结果:', results.map(r => typeof r === 'number' ? `${r}字节` : '数据'));
}

// 主演示函数
async function main() {
    console.log('🚀 QuickJS + libuv 异步I/O功能演示\n');
    console.log('这个演示展示了类似Node.js的异步功能:');
    console.log('- 异步文件读写');
    console.log('- 定时器');
    console.log('- TCP服务器');
    console.log('- 事件循环');
    console.log('- Promise支持\n');
    
    try {
        // 顺序执行演示
        await demoFileOperations();
        await demoTimers();
        await demoConcurrency();
        await demoTCPServer();
        
        console.log('\n✅ 所有演示完成!\n');
        console.log('在实际的QuickJS + libuv环境中:');
        console.log('1. 使用 import * as uv from "libuv" 加载模块');
        console.log('2. uv.fsRead() / uv.fsWrite() 进行真正的异步文件I/O');
        console.log('3. uv.createTCPServer() 创建真正的TCP服务器');
        console.log('4. uv.run() 启动libuv事件循环');
        
    } catch (err) {
        console.error('\n❌ 演示出错:', err);
    }
}

// 如果在QuickJS环境中，可以直接执行
if (typeof main === 'function') {
    main();
}