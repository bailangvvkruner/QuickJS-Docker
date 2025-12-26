# QuickJS-Docker
QuickJS JavaScript引擎 Docker

翻译官网
[[https://bellard.org/](https://bellard.org/quickjs/)](https://bellard.org/quickjs/)

# QuickJS JavaScript 引擎

## 新闻

- 2025-09-13:
  - 新版本 ([Changelog](https://bellard.org/quickjs/Changelog))

- 2025-04-26:
  - 新版本 ([Changelog](https://bellard.org/quickjs/Changelog))。大数扩展和 qjscalc 应用程序已被移除以简化代码。[BFCalc 计算器](https://bellard.org/libbf)（[web 版本](http://numcalc.com)）可以作为 qjscalc 的替代品。

- 2024-01-13:
  - 新版本 ([Changelog](https://bellard.org/quickjs/Changelog))

## 介绍

QuickJS 是一个小巧且可嵌入的 JavaScript 引擎。它支持 [ES2023](https://tc39.github.io/ecma262/2023) 规范，包括模块、异步生成器、代理和 BigInt。

主要特点：

- **小巧且易于嵌入**：只需几个 C 文件，无外部依赖，367 KiB 的 x86 代码即可实现简单的 `hello world` 程序。

- **快速解释器，启动时间极短**：在单核台式电脑上约 2 分钟内运行 ECMAScript 测试套件的 78000 个测试。运行时实例的完整生命周期在少于 300 微秒内完成。

- **几乎完整的 ES2023 支持**：包括模块、异步生成器和完整的附录 B 支持（传统 Web 兼容性）。

- **通过近 100% 的 ECMAScript 测试套件测试**：当选择 ES2023 功能时（参见 [test262.fyi](https://test262.fyi)）。

- **可以将 JavaScript 源代码编译为可执行文件**：无外部依赖。

- **使用引用计数的垃圾回收**：以减少内存使用并具有确定性行为，包含循环移除。

- **带有上下文着色的命令行解释器**：用 JavaScript 实现。

- **小型内置标准库**：包含 C 库包装器。

## 在线演示

`qjs` 可以在 [JSLinux](https://bellard.org/jslinux/vm.html?url=alpine-x86.cfg) 中运行。

## 基准测试

- [Boa 基准测试](https://boajs.dev/benchmarks)
- [JavaScript 引擎动物园](https://zoo.js.org/?arch=amd64&v8=true)

## 文档

QuickJS 文档：[HTML 版本](https://bellard.org/quickjs/quickjs.html)、[PDF 版本](https://bellard.org/quickjs/quickjs.pdf)。

## 下载

- **QuickJS 源代码**：[quickjs-2025-09-13-2.tar.xz](https://bellard.org/quickjs/quickjs-2025-09-13-2.tar.xz)
- **QuickJS 额外文件**（包含重新构建 Unicode 表所需的 Unicode 文件和 bench-v8 基准测试）：[quickjs-extras-2025-09-13.tar.xz](https://bellard.org/quickjs/quickjs-extras-2025-09-13.tar.xz)
- **官方 GitHub 仓库**：[https://github.com/bellard/quickjs](https://github.com/bellard/quickjs)
- **二进制发布**：[在此处获取](https://bellard.org/quickjs/binary_releases)
- **Cosmopolitan 二进制文件**：运行在 Linux、Mac、Windows、FreeBSD、OpenBSD、NetBSD 上，支持 ARM64 和 x86_64 架构：[quickjs-cosmo-2025-09-13.zip](https://bellard.org/quickjs/binary_releases/quickjs-cosmo-2025-09-13.zip)
- **使用 QuickJS 编译的 TypeScript 编译器**：[quickjs-typescript-5.9.3-linux-x86.tar.xz](https://bellard.org/quickjs/quickjs-typescript-5.9.3-linux-x86.tar.xz)
- **使用 QuickJS 编译的 Babel 编译器**：[quickjs-babel-linux-x86.tar.xz](https://bellard.org/quickjs/quickjs-babel-linux-x86.tar.xz)

## 子项目

QuickJS 嵌入了以下 C 库，可在其他项目中使用：

- **libregexp（正则表达式库）**：小巧快速的正则表达式库，完全兼容 JavaScript ES2023 规范。
- **libunicode（Unicode 库）**：小型 Unicode 库，支持大小写转换、Unicode 规范化、Unicode 脚本查询、Unicode 通用类别查询和所有 Unicode 二进制属性。
- **dtoa（浮点数转换库）**：小型库，实现 float64 打印和解析。

## 许可协议

QuickJS 发布于 [MIT 许可协议](https://opensource.org/licenses/MIT)。

除非另有说明，QuickJS 源代码版权所有 Fabrice Bellard 和 Charlie Gordon。

---

Fabrice Bellard - [https://bellard.org/](https://bellard.org/)
