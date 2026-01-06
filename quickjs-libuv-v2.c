/*
 * QuickJS libuv 绑定 - 改进版本
 * 实现类似Node.js的异步I/O功能
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>
#include "quickjs.h"

/* 类型定义 */
typedef struct {
    JSRuntime *rt;
    JSContext *ctx;
    uv_loop_t *loop;
    int ref_count;
} JSUVContext;

typedef struct {
    JSValue promise_resolve;
    JSValue promise_reject;
    uv_fs_t req;
    JSUVContext *js_uv_ctx;
    uint8_t *buffer;
    size_t buffer_size;
} JSUVFSRequest;

typedef struct {
    JSValue callback;
    uv_tcp_t *tcp_handle;
    JSUVContext *js_uv_ctx;
} JSUVTCPServer;

typedef struct {
    JSValue callback;
    uv_timer_t *timer_handle;
    JSUVContext *js_uv_ctx;
} JSUVTimer;

/* 全局上下文 */
static JSUVContext *global_js_uv_ctx = NULL;

/* 前向声明 */
static void js_uv_fs_req_cleanup(JSUVFSRequest *req);
static void js_uv_timer_cleanup(JSUVTimer *timer);

/* Promise 辅助函数 */
static JSValue js_uv_create_promise(JSContext *ctx, JSValue *resolve, JSValue *reject) {
    JSValue promise = JS_NewPromiseCapability(ctx, resolve);
    if (JS_IsException(promise)) {
        return JS_EXCEPTION;
    }
    return promise;
}

static void js_uv_resolve(JSContext *ctx, JSValue resolve, JSValue value) {
    if (!JS_IsUndefined(resolve) && !JS_IsNull(resolve)) {
        JS_Call(ctx, resolve, JS_UNDEFINED, 1, &value);
    }
}

static void js_uv_reject(JSContext *ctx, JSValue reject, JSValue error) {
    if (!JS_IsUndefined(reject) && !JS_IsNull(reject)) {
        JS_Call(ctx, reject, JS_UNDEFINED, 1, &error);
    }
}

/* 错误创建 */
static JSValue js_uv_new_error(JSContext *ctx, int err_code, const char *msg) {
    JSValue error = JS_NewError(ctx);
    JS_SetPropertyStr(ctx, error, "code", JS_NewInt32(ctx, err_code));
    JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, msg ? msg : uv_strerror(err_code)));
    return error;
}

/* 文件系统操作回调 */
static void js_uv_fs_cb(uv_fs_t *req) {
    JSUVFSRequest *fs_req = (JSUVFSRequest *)req->data;
    if (!fs_req) return;

    JSContext *ctx = fs_req->js_uv_ctx->ctx;
    
    if (req->result < 0) {
        // 错误处理
        JSValue error = js_uv_new_error(ctx, req->result, NULL);
        js_uv_reject(ctx, fs_req->promise_reject, error);
        JS_FreeValue(ctx, error);
    } else {
        // 成功处理
        JSValue result;
        
        switch (req->fs_type) {
            case UV_FS_READ: {
                // 返回读取的数据
                if (fs_req->buffer && req->result > 0) {
                    result = JS_NewArrayBufferCopy(ctx, fs_req->buffer, req->result);
                } else {
                    result = JS_NewArrayBuffer(ctx, 0);
                }
                break;
            }
            case UV_FS_WRITE: {
                // 返回写入的字节数
                result = JS_NewInt64(ctx, req->result);
                break;
            }
            case UV_FS_OPEN: {
                // 返回文件描述符
                result = JS_NewInt32(ctx, (int)req->result);
                break;
            }
            case UV_FS_STAT: {
                // 返回文件状态信息
                result = JS_NewObject(ctx);
                uv_stat_t *st = &req->statbuf;
                JS_SetPropertyStr(ctx, result, "size", JS_NewInt64(ctx, st->st_size));
                JS_SetPropertyStr(ctx, result, "mode", JS_NewInt64(ctx, st->st_mode));
                JS_SetPropertyStr(ctx, result, "mtime", JS_NewInt64(ctx, st->st_mtim.tv_sec));
                JS_SetPropertyStr(ctx, result, "ctime", JS_NewInt64(ctx, st->st_ctim.tv_sec));
                break;
            }
            default:
                result = JS_UNDEFINED;
        }
        
        js_uv_resolve(ctx, fs_req->promise_resolve, result);
        JS_FreeValue(ctx, result);
    }

    // 清理资源
    js_uv_fs_req_cleanup(fs_req);
}

static void js_uv_fs_req_cleanup(JSUVFSRequest *req) {
    if (req) {
        JSContext *ctx = req->js_uv_ctx->ctx;
        JS_FreeValue(ctx, req->promise_resolve);
        JS_FreeValue(ctx, req->promise_reject);
        if (req->buffer) {
            free(req->buffer);
        }
        free(req);
    }
}

/* 异步文件读取 */
static JSValue js_uv_fs_read(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    const char *filename;
    JSValue resolve, reject, promise;
    
    if (argc < 1 || !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(ctx, "filename required");
    }
    
    filename = JS_ToCString(ctx, argv[0]);
    if (!filename) return JS_EXCEPTION;
    
    // 创建Promise
    promise = js_uv_create_promise(ctx, &resolve, &reject);
    if (JS_IsException(promise)) {
        JS_FreeCString(ctx, filename);
        return JS_EXCEPTION;
    }
    
    // 创建请求结构
    JSUVFSRequest *req = calloc(1, sizeof(JSUVFSRequest));
    if (!req) {
        JS_FreeCString(ctx, filename);
        JS_FreeValue(ctx, resolve);
        JS_FreeValue(ctx, reject);
        JS_FreeValue(ctx, promise);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    req->promise_resolve = resolve;
    req->promise_reject = reject;
    req->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    req->buffer = NULL;
    req->buffer_size = 0;
    
    // 初始化libuv文件操作
    uv_fs_t *fs_req = &req->req;
    fs_req->data = req;
    
    // 异步打开文件
    int fd = uv_fs_open(req->js_uv_ctx->loop, fs_req, filename, O_RDONLY, 0, NULL);
    if (fd < 0) {
        JSValue error = js_uv_new_error(ctx, fd, NULL);
        js_uv_reject(ctx, reject, error);
        JS_FreeValue(ctx, error);
        JS_FreeCString(ctx, filename);
        js_uv_fs_req_cleanup(req);
        return promise;
    }
    
    // 获取文件大小
    uv_fs_t stat_req;
    int stat_result = uv_fs_stat(req->js_uv_ctx->loop, &stat_req, filename, NULL);
    size_t file_size = 0;
    if (stat_result == 0) {
        file_size = stat_req.statbuf.st_size;
    }
    
    if (file_size == 0) file_size = 4096; // 默认缓冲区大小
    
    // 分配缓冲区
    req->buffer = malloc(file_size);
    if (!req->buffer) {
        uv_fs_close(req->js_uv_ctx->loop, &stat_req, fd, NULL);
        JS_FreeCString(ctx, filename);
        JS_FreeValue(ctx, resolve);
        JS_FreeValue(ctx, reject);
        JS_FreeValue(ctx, promise);
        free(req);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    req->buffer_size = file_size;
    
    // 读取文件
    uv_buf_t buf = uv_buf_init((char*)req->buffer, file_size);
    int read_result = uv_fs_read(req->js_uv_ctx->loop, fs_req, fd, &buf, 1, 0, js_uv_fs_cb);
    
    if (read_result < 0) {
        JSValue error = js_uv_new_error(ctx, read_result, NULL);
        js_uv_reject(ctx, reject, error);
        JS_FreeValue(ctx, error);
        JS_FreeCString(ctx, filename);
        js_uv_fs_req_cleanup(req);
        return promise;
    }
    
    JS_FreeCString(ctx, filename);
    return promise;
}

/* 异步文件写入 */
static JSValue js_uv_fs_write(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    const char *filename;
    const char *data;
    size_t data_len;
    JSValue resolve, reject, promise;
    
    if (argc < 2 || !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(ctx, "filename and data required");
    }
    
    filename = JS_ToCString(ctx, argv[0]);
    if (!filename) return JS_EXCEPTION;
    
    // 获取数据
    if (JS_IsString(argv[1])) {
        data = JS_ToCStringLen(ctx, &data_len, argv[1]);
    } else if (JS_IsArrayBuffer(ctx, argv[1])) {
        size_t size;
        data = JS_GetArrayBuffer(ctx, &size, argv[1]);
        data_len = size;
    } else {
        JS_FreeCString(ctx, filename);
        return JS_ThrowTypeError(ctx, "data must be string or ArrayBuffer");
    }
    
    if (!data) {
        JS_FreeCString(ctx, filename);
        return JS_EXCEPTION;
    }
    
    // 创建Promise
    promise = js_uv_create_promise(ctx, &resolve, &reject);
    if (JS_IsException(promise)) {
        JS_FreeCString(ctx, filename);
        if (JS_IsString(argv[1])) JS_FreeCString(ctx, data);
        return JS_EXCEPTION;
    }
    
    // 创建请求结构
    JSUVFSRequest *req = calloc(1, sizeof(JSUVFSRequest));
    if (!req) {
        JS_FreeCString(ctx, filename);
        if (JS_IsString(argv[1])) JS_FreeCString(ctx, data);
        JS_FreeValue(ctx, resolve);
        JS_FreeValue(ctx, reject);
        JS_FreeValue(ctx, promise);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    req->promise_resolve = resolve;
    req->promise_reject = reject;
    req->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    // 初始化libuv文件操作
    uv_fs_t *fs_req = &req->req;
    fs_req->data = req;
    
    // 异步打开文件
    int fd = uv_fs_open(req->js_uv_ctx->loop, fs_req, filename, O_WRONLY | O_CREAT | O_TRUNC, 0644, NULL);
    if (fd < 0) {
        JSValue error = js_uv_new_error(ctx, fd, NULL);
        js_uv_reject(ctx, reject, error);
        JS_FreeValue(ctx, error);
        JS_FreeCString(ctx, filename);
        if (JS_IsString(argv[1])) JS_FreeCString(ctx, data);
        js_uv_fs_req_cleanup(req);
        return promise;
    }
    
    // 写入数据
    uv_buf_t buf = uv_buf_init((char*)data, data_len);
    int write_result = uv_fs_write(req->js_uv_ctx->loop, fs_req, fd, &buf, 1, 0, js_uv_fs_cb);
    
    if (write_result < 0) {
        JSValue error = js_uv_new_error(ctx, write_result, NULL);
        js_uv_reject(ctx, reject, error);
        JS_FreeValue(ctx, error);
        JS_FreeCString(ctx, filename);
        if (JS_IsString(argv[1])) JS_FreeCString(ctx, data);
        js_uv_fs_req_cleanup(req);
        return promise;
    }
    
    JS_FreeCString(ctx, filename);
    if (JS_IsString(argv[1])) JS_FreeCString(ctx, data);
    return promise;
}

/* TCP服务器连接回调 */
static void js_uv_tcp_connection_cb(uv_stream_t *server, int status) {
    JSUVTCPServer *tcp_server = (JSUVTCPServer *)server->data;
    if (!tcp_server) return;
    
    JSContext *ctx = tcp_server->js_uv_ctx->ctx;
    
    if (status < 0) {
        JSValue error = js_uv_new_error(ctx, status, NULL);
        
        if (!JS_IsUndefined(tcp_server->callback)) {
            JS_Call(ctx, tcp_server->callback, JS_UNDEFINED, 1, &error);
        }
        
        JS_FreeValue(ctx, error);
        return;
    }
    
    // 创建新的TCP连接
    uv_tcp_t *client = malloc(sizeof(uv_tcp_t));
    if (!client) return;
    
    uv_tcp_init(server->loop, client);
    
    if (uv_accept(server, (uv_stream_t*)client) == 0) {
        // 获取客户端地址
        struct sockaddr_storage addr;
        int addr_len = sizeof(addr);
        char ip[INET6_ADDRSTRLEN];
        int port = 0;
        
        if (uv_tcp_getpeername(client, (struct sockaddr*)&addr, &addr_len) == 0) {
            if (addr.ss_family == AF_INET) {
                struct sockaddr_in *sin = (struct sockaddr_in*)&addr;
                uv_ip4_name(sin, ip, sizeof(ip));
                port = ntohs(sin->sin_port);
            } else if (addr.ss_family == AF_INET6) {
                struct sockaddr_in6 *sin6 = (struct sockaddr_in6*)&addr;
                uv_ip6_name(sin6, ip, sizeof(ip));
                port = ntohs(sin6->sin6_port);
            }
        }
        
        // 调用连接回调
        if (!JS_IsUndefined(tcp_server->callback)) {
            JSValue conn_obj = JS_NewObject(ctx);
            JS_SetPropertyStr(ctx, conn_obj, "type", JS_NewString(ctx, "connection"));
            JS_SetPropertyStr(ctx, conn_obj, "from", JS_NewStringFormat(ctx, "%s:%d", ip, port));
            JS_Call(ctx, tcp_server->callback, JS_UNDEFINED, 1, &conn_obj);
            JS_FreeValue(ctx, conn_obj);
        }
        
        // 关闭连接（简单实现）
        uv_close((uv_handle_t*)client, NULL);
    } else {
        uv_close((uv_handle_t*)client, NULL);
        free(client);
    }
}

/* 创建TCP服务器 */
static JSValue js_uv_tcp_create_server(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    int port;
    JSValue callback;
    
    if (argc < 2 || !JS_IsNumber(argv[0]) || !JS_IsFunction(ctx, argv[1])) {
        return JS_ThrowTypeError(ctx, "port and callback required");
    }
    
    if (JS_ToInt32(ctx, &port, argv[0]) < 0) {
        return JS_EXCEPTION;
    }
    
    callback = JS_DupValue(ctx, argv[1]);
    
    // 创建TCP服务器结构
    JSUVTCPServer *tcp_server = calloc(1, sizeof(JSUVTCPServer));
    if (!tcp_server) {
        JS_FreeValue(ctx, callback);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    tcp_server->callback = callback;
    tcp_server->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    // 初始化TCP服务器
    tcp_server->tcp_handle = malloc(sizeof(uv_tcp_t));
    if (!tcp_server->tcp_handle) {
        JS_FreeValue(ctx, callback);
        free(tcp_server);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    uv_tcp_init(tcp_server->js_uv_ctx->loop, tcp_server->tcp_handle);
    tcp_server->tcp_handle->data = tcp_server;
    
    struct sockaddr_in addr;
    uv_ip4_addr("0.0.0.0", port, &addr);
    
    int result = uv_tcp_bind(tcp_server->tcp_handle, (const struct sockaddr*)&addr, 0);
    if (result < 0) {
        JS_FreeValue(ctx, callback);
        free(tcp_server->tcp_handle);
        free(tcp_server);
        return JS_ThrowTypeError(ctx, uv_strerror(result));
    }
    
    result = uv_listen((uv_stream_t*)tcp_server->tcp_handle, 128, js_uv_tcp_connection_cb);
    if (result < 0) {
        JS_FreeValue(ctx, callback);
        free(tcp_server->tcp_handle);
        free(tcp_server);
        return JS_ThrowTypeError(ctx, uv_strerror(result));
    }
    
    // 返回服务器对象
    JSValue server_obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, server_obj, "port", JS_NewInt32(ctx, port));
    
    // 添加close方法
    JSValue close_func = JS_NewCFunction(ctx, NULL, "close", 0);
    JS_SetPropertyStr(ctx, server_obj, "close", close_func);
    
    return server_obj;
}

/* 定时器回调 */
static void js_uv_timer_cb(uv_timer_t *handle) {
    JSUVTimer *timer = (JSUVTimer *)handle->data;
    if (!timer) return;
    
    JSContext *ctx = timer->js_uv_ctx->ctx;
    
    if (!JS_IsUndefined(timer->callback)) {
        JS_Call(ctx, timer->callback, JS_UNDEFINED, 0, NULL);
    }
    
    // 一次性定时器，完成后清理
    uv_timer_stop(handle);
    js_uv_timer_cleanup(timer);
}

static void js_uv_timer_cleanup(JSUVTimer *timer) {
    if (timer) {
        JSContext *ctx = timer->js_uv_ctx->ctx;
        JS_FreeValue(ctx, timer->callback);
        if (timer->timer_handle) {
            free(timer->timer_handle);
        }
        free(timer);
    }
}

/* 设置超时 */
static JSValue js_uv_set_timeout(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    int timeout;
    JSValue callback;
    
    if (argc < 2 || !JS_IsFunction(ctx, argv[0]) || !JS_IsNumber(argv[1])) {
        return JS_ThrowTypeError(ctx, "callback and timeout required");
    }
    
    callback = JS_DupValue(ctx, argv[0]);
    if (JS_ToInt32(ctx, &timeout, argv[1]) < 0) {
        JS_FreeValue(ctx, callback);
        return JS_EXCEPTION;
    }
    
    JSUVContext *js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    if (!js_uv_ctx || !js_uv_ctx->loop) {
        JS_FreeValue(ctx, callback);
        return JS_ThrowTypeError(ctx, "No event loop available");
    }
    
    JSUVTimer *timer = calloc(1, sizeof(JSUVTimer));
    if (!timer) {
        JS_FreeValue(ctx, callback);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    timer->callback = callback;
    timer->js_uv_ctx = js_uv_ctx;
    
    timer->timer_handle = malloc(sizeof(uv_timer_t));
    if (!timer->timer_handle) {
        JS_FreeValue(ctx, callback);
        free(timer);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    timer->timer_handle->data = timer;
    
    uv_timer_init(js_uv_ctx->loop, timer->timer_handle);
    uv_timer_start(timer->timer_handle, js_uv_timer_cb, timeout, 0);
    
    return JS_NewInt32(ctx, (intptr_t)timer);
}

/* 事件循环运行 */
static JSValue js_uv_run(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    JSUVContext *js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    if (!js_uv_ctx || !js_uv_ctx->loop) {
        return JS_ThrowTypeError(ctx, "No event loop available");
    }
    
    // 运行事件循环
    int result = uv_run(js_uv_ctx->loop, UV_RUN_DEFAULT);
    
    return JS_NewInt32(ctx, result);
}

/* 事件循环停止 */
static JSValue js_uv_stop(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    JSUVContext *js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    if (!js_uv_ctx || !js_uv_ctx->loop) {
        return JS_ThrowTypeError(ctx, "No event loop available");
    }
    
    uv_stop(js_uv_ctx->loop);
    return JS_UNDEFINED;
}

/* 模块初始化 */
static const JSCFunctionListEntry js_uv_funcs[] = {
    JS_CFUNC_DEF("fsRead", 1, js_uv_fs_read),
    JS_CFUNC_DEF("fsWrite", 2, js_uv_fs_write),
    JS_CFUNC_DEF("createTCPServer", 2, js_uv_tcp_create_server),
    JS_CFUNC_DEF("setTimeout", 2, js_uv_set_timeout),
    JS_CFUNC_DEF("run", 0, js_uv_run),
    JS_CFUNC_DEF("stop", 0, js_uv_stop),
};

static void js_uv_free_context(JSRuntime *rt, void *opaque) {
    JSUVContext *ctx = (JSUVContext *)opaque;
    if (ctx) {
        if (ctx->loop) {
            uv_loop_close(ctx->loop);
            free(ctx->loop);
        }
        free(ctx);
    }
}

static int js_uv_init(JSContext *ctx, JSModuleDef *m) {
    JSUVContext *js_uv_ctx = malloc(sizeof(JSUVContext));
    if (!js_uv_ctx) return -1;
    
    js_uv_ctx->rt = JS_GetRuntime(ctx);
    js_uv_ctx->ctx = ctx;
    js_uv_ctx->loop = malloc(sizeof(uv_loop_t));
    
    if (uv_loop_init(js_uv_ctx->loop) != 0) {
        free(js_uv_ctx->loop);
        free(js_uv_ctx);
        return -1;
    }
    
    JS_SetContextOpaque(ctx, js_uv_ctx);
    global_js_uv_ctx = js_uv_ctx;
    
    // 注册清理回调
    JS_SetRuntimeOpaque(js_uv_ctx->rt, js_uv_ctx);
    
    return JS_SetModuleExportList(ctx, m, js_uv_funcs, countof(js_uv_funcs));
}

JSModuleDef *js_init_module_libuv(JSContext *ctx, const char *module_name) {
    JSModuleDef *m = JS_NewCModule(ctx, module_name, js_uv_init);
    if (!m) return NULL;
    
    JS_AddModuleExportList(ctx, m, js_uv_funcs, countof(js_uv_funcs));
    return m;
}