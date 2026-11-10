# 项目结构与本地运行

桌面客户端在本机解码；Web 将日志交给服务端解码，私钥由服务端配置。

| 项目 | 职责 | SDK 要求 |
| --- | --- | --- |
| 根目录 Flutter 项目 | Windows、macOS 客户端 | Flutter，附带 Dart >=3.9.2 |
| `packages/xlog_decode` | 共用的纯 Dart 解码库 | Dart >=3.9.2 |
| `packages/xlog_web` | 上传文件、显示进度、下载日志 | 独立 Dart >=3.11 |
| `packages/xlog_server` | 解码、解密、任务调度和文件存储 | 独立 Dart >=3.11 |

Dart 版本均须低于 4.0，以各项目的 `pubspec.yaml` 为准。

## 本地运行

在仓库根目录执行：

```sh
dart scripts/web.dart
```

脚本启动前后端并打开 `http://localhost:18780`。页面通过同站点的 `/api` 访问后端，无需填写服务地址或密钥。按 `Ctrl+C` 停止，修改后端代码或配置后需重启。

其他命令：

```sh
dart scripts/web.dart --no-open         # 不自动打开浏览器
dart scripts/web.dart --config packages/xlog_server/server.yaml
dart scripts/web.dart build             # 构建前端
dart scripts/web.dart build-server      # 编译服务端二进制
dart scripts/web.dart build-all         # 同时构建前后端
```

脚本使用当前 Dart SDK 运行子进程，不依赖桌面项目的 Flutter 版本。

## 进一步阅读

- [部署说明](deployment.md)：构建产物、启动服务和配置反向代理。
- [服务端设计](server-architecture.md)：代码结构、任务处理和资源限制。
- [服务端配置与 API](../packages/xlog_server/README.md)。
- [解码库接口](../packages/xlog_decode/README.md)。
