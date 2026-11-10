# Xlog 解码器

**简体中文** | [English](README_EN.md)

将 Mars xlog 日志转换为可阅读的文本文件。支持加密日志、ZIP 压缩包和批量处理，提供桌面客户端、命令行，以及独立的 Jaspr Web 前端与 HTTP 服务。

## 下载使用

从 [GitHub Releases](https://github.com/arcticfox1919/xlog_decoder/releases) 下载对应平台的 ZIP，无需安装 Flutter：

- **Windows x64**：解压后运行 `XlogDecoder/xlog_decoder.exe`。请保留同目录下的 DLL 和 `data` 文件夹，压缩包已包含 Visual C++ 运行库。
- **macOS arm64**：适用于 Apple Silicon（M 系列芯片），解压后将 `XlogDecoder.app` 拖到「应用程序」目录。当前为临时签名，未经过 Apple 公证；首次打开若被系统阻止，可在「系统设置 → 隐私与安全性」中允许打开。

开发版本可在仓库 **Actions → Desktop builds → 成功的运行 → Artifacts** 下载（需要登录 GitHub，保存 30 天）。下载的 Artifact 解压后，里面是对应平台的发布 ZIP。

## 启动应用

需要安装 Flutter，Dart 版本须满足 `pubspec.yaml` 中的要求（当前为 3.9.2 或以上、低于 4.0.0）。在项目目录运行：

```sh
flutter pub get
flutter run -d windows
```

macOS 将 `windows` 换成 `macos`，Linux 换成 `linux`。桌面界面面向这三个平台，已在 Windows 环境构建验证。

## 使用方法

1. **填写私钥**：未加密日志可留空；加密日志填写服务器私钥，也可点击「从文件导入私钥」。
2. **添加文件**：拖入日志或 ZIP，或点击「选择文件」，支持多选，添加后自动处理。
3. **查看结果**：在处理记录中查看输出路径和失败原因。默认保存到输入文件所在目录，点击输出目录条目即可更改，设置会自动记忆。

例如，`app.xlog` 会生成 `app.log`。桌面界面遇到同名文件会依次使用 `app1.log`、`app2.log`，不会覆盖已有文件。

- ZIP 中的 `.xlog`、`.log`、`.bin` 会被处理，包括子目录中的文件；不处理嵌套 ZIP。每个 ZIP 会在输出目录下创建同名文件夹，例如 `logs.zip` 的结果保存到 `logs/`；文件夹已存在时自动编号为 `logs1/`、`logs2/`。ZIP 内的子目录会合并，日志同名时自动编号。
- 私钥是与日志写入端公钥配对的 **64 个十六进制字符（32 字节）**，会使用 Hive 加密保存在本机，下次启动自动填充；清空输入即可删除。加密密钥保存在系统安全存储中。没有对应私钥就无法解密加密日志。
- macOS 版本已关闭应用沙箱，拖入文件后直接保存到原目录，无需先选择输出目录。

## 界面语言

右上角语言菜单支持「跟随系统 / 简体中文 / English」，切换即时生效并自动保存。首次启动跟随系统；不支持的系统语言回退到英语。

本地化采用 [Flutter 官方方案](https://docs.flutter.dev/ui/internationalization)：`flutter_localizations`、`intl`、ARB 和 `gen-l10n`。资源位于 `lib/l10n/app_en.arb` 和 `app_zh.arb`，配置见 `l10n.yaml`。数量与动态内容使用 ICU 占位符及复数规则。界面和常见操作错误支持中英文，解码核心与系统/第三方库的原始技术诊断保留原文；本次未改动命令行文案或原生应用包名称。

扩展语言时，复制英文模板为 `app_<语言代码>.arb`，翻译所有资源并将 `languageName` 设为该语言的原生名称，然后运行 `flutter gen-l10n`。新语言会自动加入支持列表及语言菜单，无需修改条件分支。`app_localizations*.dart` 为生成文件，修改 ARB 后重新生成并一并提交。

## 客户端与 Web

桌面客户端继续在本机读取文件、保存私钥并执行解码。共享核心是纯 Dart 包 [`packages/xlog_decode`](packages/xlog_decode/README.md)，客户端和后端共用此实现。

Web 前端位于 [`packages/xlog_web`](packages/xlog_web/README.md)，使用 Jaspr 0.23.5；HTTP 后端位于 [`packages/xlog_server`](packages/xlog_server/README.md)，使用 Shelf 1.4.3 与 `shelf_router`。Shelf 由 [Dart 官方仓库](https://github.com/dart-lang/shelf)维护，也是 [`dart create -t server-shelf`](https://dart.dev/tools/dart-create) 模板采用的服务端方案。浏览器负责上传、查看任务状态和下载，解码、解密与私钥配置都由后端完成。Web 工程不依赖 Flutter 或解码库，也不提供私钥输入。**当前没有公网部署。**

Web 与服务端使用独立 Dart SDK 3.11 或以上、低于 4.0.0，在仓库根目录一键启动：

```sh
dart scripts/web.dart

# 只打包前端；产物位于 packages/xlog_web/build/jaspr/
dart scripts/web.dart build

# 构建服务端 AOT 可执行文件；build-all 同时构建前后端
dart scripts/web.dart build-server

# 使用独立 API 域名时，由部署配置指定地址
dart scripts/web.dart build --api-url https://api.example.com/
```

脚本会自动安装依赖，分别启动前后端并打开浏览器；按 `Ctrl+C` 停止。更多选项见 `dart scripts/web.dart --help`。

页面打开即可上传日志，后端自动识别加密与未加密日志，并使用后端配置的密钥解密。开发环境和部署环境都默认通过同源 `/api` 访问后端，私钥只留在服务端。Web 使用见 [Web 说明](packages/xlog_web/README.md)，二进制与反向代理配置见 [部署说明](docs/deployment.md)。

后端使用带背压和资源上限的 `decodeTo` 接口，上传和结果落临时盘，并限制运行任务数。服务端还需依据部署资源配置上传、磁盘和并发配额；合成流式基准不能替代生产负载压测。

## 命令行用法

在项目目录运行：

```sh
# 解码单个文件，默认生成 app.log
dart run bin/decode_xlog.dart app.xlog

# 解码加密日志，key.txt 中只填写十六进制私钥
dart run bin/decode_xlog.dart --key-file key.txt app.xlog

# 指定输出文件
dart run bin/decode_xlog.dart app.xlog decoded.log

# 批量处理目录中的 .xlog 文件，不含子目录
dart run bin/decode_xlog.dart --key-file key.txt ./logs

# 查看全部选项
dart run bin/decode_xlog.dart --help
```

命令行会覆盖已有的输出文件。默认遇到损坏内容会尝试继续解码；加上 `--strict` 可在遇到问题时停止。旧版 C 格式日志可加上 `--legacy c`。

## 在 Dart 代码中使用

```dart
import 'package:xlog_decode/xlog_decode.dart';

final decoder = XlogDecoder(privateKeyHex: serverPrivateKey); // 未加密时可省略私钥
final result = decoder.decode(bytes); // bytes 为 Uint8List
print(result.text);
```

`result.bytes` 是解码后的原始字节，`result.issues` 记录解码问题。此接口会持有完整输入和输出，适用于客户端现有流程或已限制大小的输入。单次解码默认最多输出 128 MiB，可通过 `maxOutputBytes` 调整。新服务端工程应直接依赖 `xlog_decode`；原 `package:xlog_decoder/xlog_decoder.dart` 入口保留为兼容再导出。

## 开发与构建

```sh
flutter analyze
flutter test
flutter build windows --release
```

构建 macOS 或 Linux 版本时，将 `windows` 换成对应平台名。解码核心位于 `packages/xlog_decode/lib/src/`，桌面功能位于 `lib/features/decoder/`。

核心库可使用同一套 Dart 单独分析和测试：

```sh
cd packages/xlog_decode
dart pub get
dart analyze
dart test
```

根目录的 `flutter test` 验证客户端；核心库的 `dart test` 验证协议解析、解密、解压与对照样本，二者都需要运行。

macOS 仅构建 arm64 版本，支持 Apple Silicon（M 系列芯片），不支持 Intel Mac。
分发压缩包内的应用文件名为 `XlogDecoder.app`，界面名称为「Xlog 解码器」。

在 macOS 上一键构建并打包：

```sh
dart scripts/build_macos.dart
```

脚本读取 `pubspec.yaml` 的版本号，生成 `build/macos/dist/Xlog-Decoder-1.0.0-macOS-arm64.zip`（文件名随版本号变化）。脚本会自动寻找运行它的 Flutter SDK，也可指定 `FLUTTER_BIN=/path/to/flutter/bin/flutter dart scripts/build_macos.dart`。

测试样本生成脚本位于 `packages/xlog_decode/test/fixtures/generators/`，仅在重新生成对照数据时使用；运行应用、构建和日常测试都不需要 Python。

### GitHub Actions 自动构建

[desktop.yml](.github/workflows/desktop.yml) 使用 Flutter 3.35.7 作为 CI 构建验证基线（本地 SDK 只需满足 `pubspec.yaml` 约束），先分别运行纯 Dart 核心库与 Flutter 客户端的静态分析和测试，再分别构建 Windows x64 和 macOS arm64。仅推送 `v*` 标签或在 Actions 中手动运行时生成下载产物；普通分支推送和 PR 不触发构建。手动运行仅生成 Actions 产物，推送版本标签才会自动发布 Release。Windows 本地也可执行 `dart scripts/build_windows.dart`，产物位于 `build/windows/dist/`。

发布正式版本时，先更新 `pubspec.yaml` 的版本号并提交，再推送匹配的标签，例如：

```sh
git tag v1.0.0
git push origin v1.0.0
```

标签必须与 `pubspec.yaml` 一致。两个平台均构建成功后，工作流自动创建 GitHub Release 并上传 ZIP；发布说明使用英文，包含下载与签名说明，以及对应源代码提交的链接。带预发布后缀的标签（例如 `v1.0.1-beta.1`）会创建预发布版本。使用仓库自带的 `GITHUB_TOKEN`，无需配置额外 Secret；仓库需允许 GitHub Actions 运行和工作流申请 `contents: write` 权限。当前不包含 Windows 代码签名或 Apple Developer ID 签名与公证。
