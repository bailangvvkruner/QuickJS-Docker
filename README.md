# QuickJS-Docker
QuickJS JavaScript引擎 Docker

翻译官网
[[https://bellard.org/](https://bellard.org/quickjs/)](https://bellard.org/quickjs/)

# QuickJS JavaScript引擎
新闻
2025-09-13：
新版本发布（更新日志）
2025-04-26：
新版本发布（更新日志）。为了简化代码，移除了大数扩展和qjscalc应用程序。BFCalc计算器（网页版）可以作为qjscalc的替代品。
2024-01-13：
新版本发布（更新日志）

## 简介
QuickJS是一个小型且可嵌入的JavaScript引擎。它支持ES2023规范，包括模块、异步生成器、代理和BigInt。

## 主要特性：
- **小巧且易于嵌入**：仅需几个C文件，无外部依赖，简单hello world程序在x86架构上仅需367 KiB代码。
- **快速的解释器，启动时间极低**：在桌面单核CPU上运行ECMAScript测试套件的78000个测试仅需约2分钟。运行时实例的完整生命周期在300微秒内完成。
- **几乎完整的ES2023支持**：包括模块、异步生成器和完整的Annex B支持（传统Web兼容性）。
- **在选择ES2023功能时，通过近100%的ECMAScript测试套件测试**（参见test262.fyi）。
- **可以将JavaScript源代码编译为无需外部依赖的可执行文件**。
- **使用引用计数进行垃圾回收**（以减少内存使用并具有确定性行为）并带有循环检测移除功能。
- **命令行解释器**，具有用JavaScript实现的上下文着色功能。
- **小型内置标准库**，带有C库包装器。

## 在线演示
qjs可以在JSLinux中运行。

## 基准测试
- Boa基准测试
- JavaScript引擎动物园

## 文档
QuickJS文档：HTML版本，PDF版本。

## 下载
- QuickJS源代码：quickjs-2025-09-13-2.tar.xz
- QuickJS额外文件（包含重建Unicode表所需的Unicode文件和bench-v8基准测试）：quickjs-extras-2025-09-13.tar.xz
- 官方GitHub仓库。
- 二进制版本可在此处获取。
- 适用于Linux、Mac、Windows、FreeBSD、OpenBSD、NetBSD的Cosmopolitan二进制文件，支持ARM64和x86_64架构：quickjs-cosmo-2025-09-13.zip。
- 使用QuickJS编译的Typescript编译器：quickjs-typescript-5.9.3-linux-x86.tar.xz
- 使用QuickJS编译的Babel编译器：quickjs-babel-linux-x86.tar.xz

## 子项目
QuickJS嵌入了以下C库，可在其他项目中使用：
- libregexp：小型快速的正则表达式库，完全符合Javascript ES2023规范。
- libunicode：小型Unicode库，支持大小写转换、Unicode规范化、Unicode脚本查询、Unicode通用类别查询和所有Unicode二进制属性。
- dtoa：实现float64打印和解析的小型库。

## 许可
QuickJS根据MIT许可证发布。
除非另有说明，QuickJS源代码版权归Fabrice Bellard和Charlie Gordon所有。

Fabrice Bellard - [https://bellard.org/](https://bellard.org/quickjs/)
