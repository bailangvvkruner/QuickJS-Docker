/*
 * QuickJS libuv 绑定头文件
 */

#ifndef QUICKJS_LIBUV_H
#define QUICKJS_LIBUV_H

#include "quickjs.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 初始化libuv模块 */
JSModuleDef *js_init_module_libuv(JSContext *ctx, const char *module_name);

#ifdef __cplusplus
}
#endif

#endif /* QUICKJS_LIBUV_H */