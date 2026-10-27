# Xlog 解码器

将 Mars xlog 日志转换为可阅读的文本文件。支持加密日志、ZIP 压缩包和批量处理，提供桌面界面与命令行两种用法。

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
import 'package:xlog_decoder/xlog_decoder.dart';

final decoder = XlogDecoder(privateKeyHex: serverPrivateKey); // 未加密时可省略私钥
final result = decoder.decode(bytes); // bytes 为 Uint8List
print(result.text);
```

`result.bytes` 是解码后的原始字节，`result.issues` 记录解码问题。单次解码默认最多输出 128 MiB，可通过 `maxOutputBytes` 调整。

## 开发与构建

```sh
flutter analyze
flutter test
flutter build windows --release
```

构建 macOS 或 Linux 版本时，将 `windows` 换成对应平台名。解码核心位于 `lib/core/xlog/`，桌面功能位于 `lib/features/decoder/`。
