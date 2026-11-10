# Xlog Web

浏览器界面负责选择日志、上传、展示进度和下载结果；解码与解密在服务端完成。页面支持中英文，只展示“解密密钥由后端配置，系统自动识别日志并完成解码或解密”的说明，不接收或保存私钥。

## 本地开发

在仓库根目录运行：

```sh
dart scripts/web.dart

# 自定义端口或后端配置
dart scripts/web.dart --no-open --web-port 18782 --server-port 18783
dart scripts/web.dart --config packages/xlog_server/server.yaml
```

打开 `http://localhost:18780` 即可使用。开发代理将 `/api` 转发到后端，页面自动加载上传限额，并提示解密密钥由后端配置；服务不可用时显示重试。按 `Ctrl+C` 停止前后端。

使用独立 Dart SDK 3.11 或以上、低于 4.0.0，无需安装 Flutter。Jaspr、builder、CLI 与 test 使用最新稳定版 0.23.5。桌面客户端和共享解码核心保留各自较低的 SDK 要求。

## 构建与部署

```sh
dart scripts/web.dart build          # 前端静态文件
dart scripts/web.dart build-server   # 服务端 AOT 二进制
dart scripts/web.dart build-all      # 两者一起构建
```

前端输出为 `packages/xlog_web/build/jaspr/`，服务端输出为 `build/server/xlog_server`（Windows 为 `.exe`）。通常由同一个站点提供前端，并将 `/api` 反向代理到后端，浏览器使用同源地址。

部署环境确实使用独立 API 域名时，可由构建配置指定：

```sh
dart scripts/web.dart build --api-url https://api.example.com/
```

该值属于部署配置，页面不提供服务地址设置。详细示例见 [部署说明](../../docs/deployment.md)。

## 代码组织

| 位置 | 职责 |
| --- | --- |
| `lib/app.dart` | 页面组合、依赖装配与生命周期 |
| `lib/browser/` | 浏览器环境、语言持久化和原生文件适配 |
| `lib/features/decoder/domain/` | 任务模型和 API 契约 |
| `lib/features/decoder/application/` | 初始化、上传、轮询、取消和历史状态 |
| `lib/features/decoder/data/` | HTTP 请求与浏览器原生文件上传 |
| `lib/features/decoder/presentation/` | 页头、上传、解码说明、错误和历史组件 |
| `lib/l10n/strings.dart` | 中英文文案 |

应用服务可替换 API 工厂进行独立测试。浏览器上传直接发送原生 File，下载使用结果链接，均不将完整文件聚合到 JavaScript 内存。

## 检查

在 `packages/xlog_web` 中执行：

```sh
dart analyze
dart test
dart test --platform chrome test/app_browser_test.dart
```

Web 与服务端使用独立 Dart SDK 在本地测试和构建，不通过 GitHub Actions 打包。
