/*
 * QuickJS libuv 绑定
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
    JSValue callback;
    JSValue promise;
    uv_fs_t req;
    JSUVContext *js_uv_ctx;
} JSUVFSRequest;

typedef struct {
    JSValue callback;
    uv_tcp_t *tcp_handle;
    JSUVContext *js_uv_ctx;
} JSUVTCPServer;

/* 全局事件循环 */
static uv_loop_t *global_loop = NULL;

/* 前向声明 */
static JSClassID js_uv_loop_class_id;
static JSClassID js_uv_fs_class_id;
static JSClassID js_uv_tcp_class_id;

/* 工具函数 */
static void js_uv_free_loop(JSRuntime *rt, void *opaque) {
    JSUVContext *ctx = (JSUVContext *)opaque;
    if (ctx) {
        if (ctx->loop) {
            uv_loop_close(ctx->loop);
            free(ctx->loop);
        }
        free(ctx);
    }
}

/* Promise 辅助函数 */
static JSValue js_uv_new_promise(JSContext *ctx, JSValue *resolving_funcs) {
    return JS_NewPromiseCapability(ctx, resolving_funcs);
}

static void js_uv_resolve_promise(JSContext *ctx, JSValue promise, JSValue value) {
    JSValue resolve_func = JS_GetPropertyStr(ctx, promise, "resolve");
    if (!JS_IsUndefined(resolve_func)) {
        JS_Call(ctx, resolve_func, JS_UNDEFINED, 1, &value);
    }
    JS_FreeValue(ctx, resolve_func);
}

static void js_uv_reject_promise(JSContext *ctx, JSValue promise, JSValue error) {
    JSValue reject_func = JS_GetPropertyStr(ctx, promise, "reject");
    if (!JS_IsUndefined(reject_func)) {
        JS_Call(ctx, reject_func, JS_UNDEFINED, 1, &error);
    }
    JS_FreeValue(ctx, reject_func);
}

/* 文件系统操作回调 */
static void js_uv_fs_cb(uv_fs_t *req) {
    JSUVFSRequest *fs_req = (JSUVFSRequest *)req->data;
    if (!fs_req) return;

    JSContext *ctx = fs_req->js_uv_ctx->ctx;
    
    if (req->result < 0) {
        // 错误处理
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(req->result)));
        js_uv_reject_promise(ctx, fs_req->promise, error);
        JS_FreeValue(ctx, error);
    } else {
        // 成功处理
        JSValue result;
        
        switch (req->fs_type) {
            case UV_FS_READ: {
                // 返回读取的数据
                result = JS_NewArrayBufferCopy(ctx, (const uint8_t*)req->ptr, req->result);
                break;
            }
            case UV_FS_WRITE: {
                // 返回写入的字节数
                result = JS_NewInt64(ctx, req->result);
                break;
            }
            case UV_FS_STAT: {
                // 返回文件状态信息
                result = JS_NewObject(ctx);
                uv_stat_t *st = &req->statbuf;
                JS_SetPropertyStr(ctx, result, "size", JS_NewInt64(ctx, st->st_size));
                JS_SetPropertyStr(ctx, result, "mode", JS_NewInt64(ctx, st->st_mode));
                JS_SetPropertyStr(ctx, result, "mtime", JS_NewInt64(ctx, st->st_mtim.tv_sec));
                break;
            }
            default:
                result = JS_UNDEFINED;
        }
        
        js_uv_resolve_promise(ctx, fs_req->promise, result);
        JS_FreeValue(ctx, result);
    }

    // 清理
    JS_FreeValue(ctx, fs_req->callback);
    JS_FreeValue(ctx, fs_req->promise);
    free(fs_req);
}

/* 异步文件读取 */
static JSValue js_uv_fs_read(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    const char *filename;
    JSValue promise, resolving_funcs[2];
    
    if (argc < 1 || !JS_IsString(argv[0])) {
        return JS_ThrowTypeError(ctx, "filename required");
    }
    
    filename = JS_ToCString(ctx, argv[0]);
    if (!filename) return JS_EXCEPTION;
    
    // 创建Promise
    promise = js_uv_new_promise(ctx, resolving_funcs);
    
    // 创建请求结构
    JSUVFSRequest *req = malloc(sizeof(JSUVFSRequest));
    if (!req) {
        JS_FreeCString(ctx, filename);
        JS_FreeValue(ctx, resolving_funcs[0]);
        JS_FreeValue(ctx, resolving_funcs[1]);
        JS_FreeValue(ctx, promise);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    req->callback = JS_UNDEFINED;
    req->promise = promise;
    req->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    // 初始化libuv文件操作
    uv_fs_t *fs_req = &req->req;
    fs_req->data = req;
    
    // 异步打开并读取文件
    int fd = uv_fs_open(NULL, fs_req, filename, O_RDONLY, 0, NULL);
    if (fd < 0) {
        // 立即拒绝promise
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(fd)));
        js_uv_reject_promise(ctx, promise, error);
        JS_FreeValue(ctx, error);
        free(req);
        JS_FreeCString(ctx, filename);
        JS_FreeValue(ctx, resolving_funcs[0]);
        JS_FreeValue(ctx, resolving_funcs[1]);
        return promise;
    }
    
    // 读取文件内容
    uv_fs_read(NULL, fs_req, fd, NULL, 0, 0, js_uv_fs_cb);
    
    JS_FreeCString(ctx, filename);
    JS_FreeValue(ctx, resolving_funcs[0]);
    JS_FreeValue(ctx, resolving_funcs[1]);
    
    return promise;
}

/* 异步文件写入 */
static JSValue js_uv_fs_write(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    const char *filename;
    const char *data;
    size_t data_len;
    JSValue promise, resolving_funcs[2];
    
    if (argc < 2 || !JS_IsString(argv[0]) || !JS_IsString(argv[1])) {
        return JS_ThrowTypeError(ctx, "filename and data required");
    }
    
    filename = JS_ToCString(ctx, argv[0]);
    data = JS_ToCStringLen(ctx, &data_len, argv[1]);
    
    if (!filename || !data) {
        if (filename) JS_FreeCString(ctx, filename);
        if (data) JS_FreeCString(ctx, data);
        return JS_EXCEPTION;
    }
    
    promise = js_uv_new_promise(ctx, resolving_funcs);
    
    JSUVFSRequest *req = malloc(sizeof(JSUVFSRequest));
    if (!req) {
        JS_FreeCString(ctx, filename);
        JS_FreeCString(ctx, data);
        JS_FreeValue(ctx, resolving_funcs[0]);
        JS_FreeValue(ctx, resolving_funcs[1]);
        JS_FreeValue(ctx, promise);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    req->callback = JS_UNDEFINED;
    req->promise = promise;
    req->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    uv_fs_t *fs_req = &req->req;
    fs_req->data = req;
    
    // 异步打开并写入文件
    int fd = uv_fs_open(NULL, fs_req, filename, O_WRONLY | O_CREAT | O_TRUNC, 0644, NULL);
    if (fd < 0) {
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(fd)));
        js_uv_reject_promise(ctx, promise, error);
        JS_FreeValue(ctx, error);
        free(req);
        JS_FreeCString(ctx, filename);
        JS_FreeCString(ctx, data);
        JS_FreeValue(ctx, resolving_funcs[0]);
        JS_FreeValue(ctx, resolving_funcs[1]);
        return promise;
    }
    
    // 写入数据
    uv_buf_t buf = uv_buf_init((char*)data, data_len);
    uv_fs_write(NULL, fs_req, fd, &buf, 1, 0, js_uv_fs_cb);
    
    JS_FreeCString(ctx, filename);
    JS_FreeCString(ctx, data);
    JS_FreeValue(ctx, resolving_funcs[0]);
    JS_FreeValue(ctx, resolving_funcs[1]);
    
    return promise;
}

/* TCP服务器创建 */
static void js_uv_tcp_connection_cb(uv_stream_t *server, int status) {
    JSUVTCPServer *tcp_server = (JSUVTCPServer *)server->data;
    if (!tcp_server) return;
    
    JSContext *ctx = tcp_server->js_uv_ctx->ctx;
    
    if (status < 0) {
        JSValue error = JS_NewError(ctx);
        JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, uv_strerror(status)));
        
        // 调用错误回调
        if (!JS_IsUndefined(tcp_server->callback)) {
            JS_Call(ctx, tcp_server->callback, JS_UNDEFINED, 1, &error);
        }
        
        JS_FreeValue(ctx, error);
        return;
    }
    
    // 创建新的TCP连接
    uv_tcp_t *client = malloc(sizeof(uv_tcp_t));
    uv_tcp_init(server->loop, client);
    
    if (uv_accept(server, (uv_stream_t*)client) == 0) {
        // 调用连接回调
        if (!JS_IsUndefined(tcp_server->callback)) {
            JSValue conn_obj = JS_NewObject(ctx);
            JS_SetPropertyStr(ctx, conn_obj, "type", JS_NewString(ctx, "connection"));
            JS_Call(ctx, tcp_server->callback, JS_UNDEFINED, 1, &conn_obj);
            JS_FreeValue(ctx, conn_obj);
        }
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
    JSUVTCPServer *tcp_server = malloc(sizeof(JSUVTCPServer));
    if (!tcp_server) {
        JS_FreeValue(ctx, callback);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    tcp_server->callback = callback;
    tcp_server->js_uv_ctx = (JSUVContext *)JS_GetContextOpaque(ctx);
    
    // 初始化TCP服务器
    tcp_server->tcp_handle = malloc(sizeof(uv_tcp_t));
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
    JS_SetPropertyStr(ctx, server_obj, "close", JS_NewCFunction(ctx, NULL, "close", 0));
    
    return server_obj;
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

/* 定时器 */
static void js_uv_timer_cb(uv_timer_t *handle) {
    JSValue *callback = (JSValue *)handle->data;
    if (callback) {
        JSContext *ctx = (JSContext *)uv_timer_get_data(handle);
        JS_Call(ctx, *callback, JS_UNDEFINED, 0, NULL);
    }
}

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
    
    uv_timer_t *timer = malloc(sizeof(uv_timer_t));
    if (!timer) {
        JS_FreeValue(ctx, callback);
        return JS_ThrowOutOfMemory(ctx);
    }
    
    uv_timer_init(js_uv_ctx->loop, timer);
    timer->data = &callback;  // 注意：这里需要更复杂的内存管理
    
    uv_timer_start(timer, js_uv_timer_cb, timeout, 0);
    
    return JS_NewInt32(ctx, (intptr_t)timer);
}

/* 模块初始化 */
static const JSCFunctionListEntry js_uv_funcs[] = {
    JS_CFUNC_DEF("fsRead", 1, js_uv_fs_read),
    JS_CFUNC_DEF("fsWrite", 2, js_uv_fs_write),
    JS_CFUNC_DEF("createTCPServer", 2, js_uv_tcp_create_server),
    JS_CFUNC_DEF("run", 0, js_uv_run),
    JS_CFUNC_DEF("stop", 0, js_uv_stop),
    JS_CFUNC_DEF("setTimeout", 2, js_uv_set_timeout),
};

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
    
    return JS_SetModuleExportList(ctx, m, js_uv_funcs, countof(js_uv_funcs));
}

JSModuleDef *js_init_module_libuv(JSContext *ctx, const char *module_name) {
    JSModuleDef *m = JS_NewCModule(ctx, module_name, js_uv_init);
    if (!m) return NULL;
    
    JS_AddModuleExportList(ctx, m, js_uv_funcs, countof(js_uv_funcs));
    return m;
}