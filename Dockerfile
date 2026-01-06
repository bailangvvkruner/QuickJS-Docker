# QuickJS + libuv Docker构建
FROM alpine:latest AS builder

# 安装构建依赖
RUN apk add --no-cache \
    build-base \
    curl \
    tar \
    xz \
    binutils \
    pkgconfig \
    libuv-dev

# 下载并构建QuickJS + libuv
RUN set -eux \
    # 下载QuickJS
    && curl -L https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz | tar -xJf - -C /tmp \
    && cd /tmp/quickjs-* \
    \
    # 下载额外文件
    && curl -L https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz | tar -xJf - -C /tmp \
    \
    # 构建QuickJS核心
    && make -j$(nproc) qjs \
    \
    # 创建libuv扩展源代码
    && cat > quickjs-libuv.c << 'LIBUV_EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>
#include "quickjs.h"

typedef struct {
    JSRuntime *rt;
    JSContext *ctx;
    uv_loop_t *loop;
} JSUVContext;

typedef struct {
    JSValue promise_resolve;
    JSValue promise_reject;
    uv_fs_t req;
    JSUVContext *js_uv_ctx;
    uint8_t *buffer;
} JSUVFSRequest;

static JSValue js_uv_create_promise(JSContext *ctx, JSValue *resolve, JSValue *reject) {
    return JS_NewPromiseCapability(ctx, resolve);
}

static void js_uv_resolve(JSContext *ctx, JSValue resolve, JSValue value) {
    if (!JS_IsUndefined(resolve)) {
        JS_Call(ctx, resolve, JS_UNDEFINED, 1, &value);
    }
}

static void js_uv_reject(JSContext *ctx, JSValue reject, JSValue error) {
    if (!JS_IsUndefined(reject)) {
        JS_Call(ctx, reject, JS_UNDEFINED, 1, &error);
    }
}

static void js_uv_fs_req_cleanup(JSUVFSRequest *req) {
    if (req) {
        JSContext *ctx = req->js_uv_ctx->ctx;
        JS_FreeValue(ctx, req->promise_resolve);
        JS_FreeValue(ctx, req->promise_reject);
        if (req->buffer) free(req->buffer);
        free(req);
    }
}

static void js_uv_fs_cb(uv_fs_t *req) {
    JSUVFSRequest *fs_req = (JSUVFSRequest *)req->data;
    if (!fs_req) return;

    JSContext *ctx = fs_req->js_uv_ctx->ctx;
    
    if (req->result < 0) {
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(req->result)));
        js_uv_reject(ctx, fs_req->promise_reject, error);
        JS_FreeValue(ctx, error);
    } else {
        JSValue result;
        switch (req->fs_type) {
            case UV_FS_READ:
                result = req->result > 0 ? 
                    JS_NewArrayBufferCopy(ctx, fs_req->buffer, req->result) :
                    JS_NewArrayBuffer(ctx, 0);
                break;
            case UV_FS_WRITE:
                result = JS_NewInt64(ctx, req->result);
                break;
            default:
                result = JS_UNDEFINED;
        }
        js_uv_resolve(ctx, fs_req->promise_resolve, result);
        JS_FreeValue(ctx, result);
    }
    js_uv_fs_req_cleanup(fs_req);
}

static JSValue js_uv_fs_read(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    const char *filename;
    JSValue resolve, reject, promise;
    
    if (argc < 1 || !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(ctx, "filename required");
    }
    
    filename = JS_ToCString(ctx, argv[0]);
    promise = js_uv_create_promise(ctx, &resolve, &reject);
    
    JSUVFSRequest *req = calloc(1, sizeof(JSUVFSRequest));
    req->promise_resolve = resolve;
    req->promise_reject = reject;
    req->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    uv_fs_t *fs_req = &req->req;
    fs_req->data = req;
    
    int fd = uv_fs_open(req->js_uv_ctx->loop, fs_req, filename, O_RDONLY, 0, NULL);
    if (fd < 0) {
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(fd)));
        js_uv_reject(ctx, reject, error);
        JS_FreeValue(ctx, error);
        JS_FreeCString(ctx, filename);
        js_uv_fs_req_cleanup(req);
        return promise;
    }
    
    req->buffer = malloc(4096);
    uv_buf_t buf = uv_buf_init((char*)req->buffer, 4096);
    uv_fs_read(req->js_uv_ctx->loop, fs_req, fd, &buf, 1, 0, js_uv_fs_cb);
    
    JS_FreeCString(ctx, filename);
    return promise;
}

static JSValue js_uv_fs_write(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    const char *filename;
    const char *data;
    size_t data_len;
    JSValue resolve, reject, promise;
    
    if (argc < 2 || !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(ctx, "filename and data required");
    }
    
    filename = JS_ToCString(ctx, argv[0]);
    data = JS_ToCStringLen(ctx, &data_len, argv[1]);
    promise = js_uv_create_promise(ctx, &resolve, &reject);
    
    JSUVFSRequest *req = calloc(1, sizeof(JSUVFSRequest));
    req->promise_resolve = resolve;
    req->promise_reject = reject;
    req->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    uv_fs_t *fs_req = &req->req;
    fs_req->data = req;
    
    int fd = uv_fs_open(req->js_uv_ctx->loop, fs_req, filename, O_WRONLY | O_CREAT | O_TRUNC, 0644, NULL);
    if (fd < 0) {
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(fd)));
        js_uv_reject(ctx, reject, error);
        JS_FreeValue(ctx, error);
        JS_FreeCString(ctx, filename);
        JS_FreeCString(ctx, data);
        js_uv_fs_req_cleanup(req);
        return promise;
    }
    
    uv_buf_t buf = uv_buf_init((char*)data, data_len);
    uv_fs_write(req->js_uv_ctx->loop, fs_req, fd, &buf, 1, 0, js_uv_fs_cb);
    
    JS_FreeCString(ctx, filename);
    JS_FreeCString(ctx, data);
    return promise;
}

static void js_uv_timer_cb(uv_timer_t *handle) {
    JSValue *callback = (JSValue *)handle->data;
    if (callback) {
        JSContext *ctx = (JSContext *)uv_timer_get_data(handle);
        JS_Call(ctx, *callback, JS_UNDEFINED, 0, NULL);
        JS_FreeValue(ctx, *callback);
        free(callback);
        free(handle);
    }
}

static JSValue js_uv_set_timeout(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    int timeout;
    JSValue callback;
    
    if (argc < 2 || !JS_IsFunction(ctx, argv[0]) || !JS_IsNumber(argv[1])) {
        return JS_ThrowTypeError(ctx, "callback and timeout required");
    }
    
    callback = JS_DupValue(ctx, argv[0]);
    JS_ToInt32(ctx, &timeout, argv[1]);
    
    JSUVContext *js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    uv_timer_t *timer = malloc(sizeof(uv_timer_t));
    JSValue *cb_ptr = malloc(sizeof(JSValue));
    *cb_ptr = callback;
    
    timer->data = cb_ptr;
    uv_timer_init(js_uv_ctx->loop, timer);
    uv_timer_start(timer, js_uv_timer_cb, timeout, 0);
    
    return JS_NewInt32(ctx, 1);
}

static JSValue js_uv_run(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    JSUVContext *js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    if (!js_uv_ctx || !js_uv_ctx->loop) {
        return JS_ThrowTypeError(ctx, "No event loop available");
    }
    uv_run(js_uv_ctx->loop, UV_RUN_DEFAULT);
    return JS_UNDEFINED;
}

static JSValue js_uv_stop(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    JSUVContext *js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    if (js_uv_ctx && js_uv_ctx->loop) {
        uv_stop(js_uv_ctx->loop);
    }
    return JS_UNDEFINED;
}

typedef struct {
    JSValue callback;
    uv_tcp_t *tcp_handle;
    JSUVContext *js_uv_ctx;
} JSUVTCPServer;

static void js_uv_tcp_connection_cb(uv_stream_t *server, int status) {
    JSUVTCPServer *tcp_server = (JSUVTCPServer *)server->data;
    if (!tcp_server) return;
    
    JSContext *ctx = tcp_server->js_uv_ctx->ctx;
    
    if (status >= 0) {
        uv_tcp_t *client = malloc(sizeof(uv_tcp_t));
        uv_tcp_init(server->loop, client);
        
        if (uv_accept(server, (uv_stream_t*)client) == 0) {
            if (!JS_IsUndefined(tcp_server->callback)) {
                JSValue conn_obj = JS_NewObject(ctx);
                JS_SetPropertyStr(ctx, conn_obj, "type", JS_NewString(ctx, "connection"));
                JS_Call(ctx, tcp_server->callback, JS_UNDEFINED, 1, &conn_obj);
                JS_FreeValue(ctx, conn_obj);
            }
            uv_close((uv_handle_t*)client, NULL);
        } else {
            uv_close((uv_handle_t*)client, NULL);
            free(client);
        }
    }
}

static JSValue js_uv_tcp_create_server(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    int port;
    JSValue callback;
    
    if (argc < 2 || !JS_IsNumber(argv[0]) || !JS_IsFunction(ctx, argv[1])) {
        return JS_ThrowTypeError(ctx, "port and callback required");
    }
    
    JS_ToInt32(ctx, &port, argv[0]);
    callback = JS_DupValue(ctx, argv[1]);
    
    JSUVTCPServer *tcp_server = calloc(1, sizeof(JSUVTCPServer));
    tcp_server->callback = callback;
    tcp_server->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    tcp_server->tcp_handle = malloc(sizeof(uv_tcp_t));
    uv_tcp_init(tcp_server->js_uv_ctx->loop, tcp_server->tcp_handle);
    tcp_server->tcp_handle->data = tcp_server;
    
    struct sockaddr_in addr;
    uv_ip4_addr("0.0.0.0", port, &addr);
    
    uv_tcp_bind(tcp_server->tcp_handle, (const struct sockaddr*)&addr, 0);
    uv_listen((uv_stream_t*)tcp_server->tcp_handle, 128, js_uv_tcp_connection_cb);
    
    JSValue server_obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, server_obj, "port", JS_NewInt32(ctx, port));
    return server_obj;
}

static const JSCFunctionListEntry js_uv_funcs[] = {
    JS_CFUNC_DEF("fsRead", 1, js_uv_fs_read),
    JS_CFUNC_DEF("fsWrite", 2, js_uv_fs_write),
    JS_CFUNC_DEF("createTCPServer", 2, js_uv_tcp_create_server),
    JS_CFUNC_DEF("setTimeout", 2, js_uv_set_timeout),
    JS_CFUNC_DEF("run", 0, js_uv_run),
    JS_CFUNC_DEF("stop", 0, js_uv_stop),
};

static int js_uv_init(JSContext *ctx, JSModuleDef *m) {
    JSUVContext *js_uv_ctx = malloc(sizeof(JSUVContext));
    js_uv_ctx->rt = JS_GetRuntime(ctx);
    js_uv_ctx->ctx = ctx;
    js_uv_ctx->loop = malloc(sizeof(uv_loop_t));
    uv_loop_init(js_uv_ctx->loop);
    JS_SetContextOpaque(ctx, js_uv_ctx);
    return JS_SetModuleExportList(ctx, m, js_uv_funcs, countof(js_uv_funcs));
}

JSModuleDef *js_init_module_libuv(JSContext *ctx, const char *module_name) {
    JSModuleDef *m = JS_NewCModule(ctx, module_name, js_uv_init);
    if (!m) return NULL;
    JS_AddModuleExportList(ctx, m, js_uv_funcs, countof(js_uv_funcs));
    return m;
}
LIBUV_EOF

    # 编译带libuv的QuickJS
    && gcc -g -Wall -O2 -DCONFIG_VERSION=\"2025-09-13\" \
        -I. \
        quickjs.c libregexp.c libunicode.c cutils.c qjs.c quickjs-libuv.c \
        -o qjs-libuv \
        -lm -ldl -lpthread $(pkg-config --libs libuv) \
    \
    && strip --strip-all qjs-libuv \
    && mv qjs-libuv /qjs-libuv-static

# 运行阶段
FROM alpine:latest

# 安装运行时依赖
RUN apk add --no-cache libuv

# 复制构建产物
COPY --from=builder /qjs-libuv-static /qjs

# 创建工作目录和示例
RUN mkdir -p /bench && cd /bench \
    && cat > example-libuv.js << 'EXAMPLE_EOF'
// QuickJS + libuv 示例代码
import * as uv from "libuv";

console.log("=== QuickJS libuv 异步I/O演示 ===\n");

async function testFileRead() {
    console.log("1. 测试异步文件读取...");
    try {
        await uv.fsWrite("/tmp/test.txt", "Hello from QuickJS libuv!");
        console.log("   ✓ 写入测试文件成功");
        const data = await uv.fsRead("/tmp/test.txt");
        console.log("   ✓ 读取内容:", new TextDecoder().decode(data));
    } catch (err) {
        console.error("   ✗ 文件操作失败:", err.message);
    }
}

function testTimers() {
    console.log("\n2. 测试定时器...");
    uv.setTimeout(() => console.log("   ✓ 1秒后执行的定时器"), 1000);
    uv.setTimeout(() => console.log("   ✓ 2秒后执行的定时器"), 2000);
}

function testTCPServer() {
    console.log("\n3. 测试TCP服务器...");
    const server = uv.createTCPServer(8080, (conn) => {
        if (conn.type === "connection") console.log("   ✓ 收到TCP连接");
    });
    console.log("   ✓ TCP服务器启动在端口 8080");
    uv.setTimeout(() => {
        console.log("   ✓ 5秒后停止服务器");
        uv.stop();
    }, 5000);
}

async function main() {
    await testFileRead();
    testTimers();
    testTCPServer();
    console.log("\n=== 启动事件循环 ===");
    console.log("按 Ctrl+C 退出\n");
    uv.run();
}

main().catch(console.error);
EXAMPLE_EOF

WORKDIR /bench
ENTRYPOINT ["/qjs", "example-libuv.js"]
