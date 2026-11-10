# xlog_decode

纯 Dart 的 Mars xlog 帧解析、解密与解压库，供桌面客户端和 Dart 服务端共用。核心只处理日志字节和解码状态，不依赖 Flutter、本机插件或 HTTP 框架。当前提供解码、解密能力，不包含 xlog 编码器。

## 依赖与入口

当前为仓库内路径包，最低 Dart SDK 为 3.9.2：

```yaml
dependencies:
  xlog_decode:
    path: ../xlog_decoder/packages/xlog_decode
```

路径相对于调用方的 `pubspec.yaml`，按实际目录调整。后端直接引用此包，避免把根目录 Flutter 应用作为依赖。

```dart
import 'package:xlog_decode/xlog_decode.dart';
```

公开入口导出 `XlogDecoder`、`XlogDecodeResult`、格式选项、块信息、诊断类型以及流式接口配置和摘要。`lib/src/` 是内部实现。根应用的 `package:xlog_decoder/xlog_decoder.dart` 继续兼容再导出核心公共接口。

## 有界输入的字节接口

```dart
final decoder = XlogDecoder(
  privateKeyHex: serverPrivateKey,
  strict: true,
  maxOutputBytes: 128 * 1024 * 1024,
);
final result = decoder.decode(bytes); // Uint8List
print(result.text);
```

未加密日志可省略私钥。私钥必须是有效的 secp256k1 32 字节标量，以 64 个十六进制字符表示。`result.bytes` 保留精确解码字节，`result.blocks` 和 `result.issues` 分别提供块信息及恢复诊断。默认沿用 Mars Python 脚本格式；旧版 C 格式需选择 `XlogLegacyFormat.c`。

`decode` 会持有完整输入和输出，适用于客户端现有流程或事先限制大小的输入。大文件后端应使用下面的流式接口。

## 自动识别与多密钥

服务端可传入 `XlogDecoder(privateKeysHex: configuredKeys)`。解码器按每帧标识识别明文、DEFLATE、Zstandard 与加密压缩块；同一文件可以混合明文和加密块，也可以包含使用不同服务端密钥生成的块。候选只在当前帧内依次尝试，不会按每个密钥重复读取整个文件。

显式传入 `privateKeysHex`（包括空集合）启用自动模式。加密候选必须通过完整压缩帧校验；DEFLATE 不允许未消费的尾随数据。没有候选、全部候选失败，或不同候选得到不同的有效内容时，`decode` 与 `decodeTo` 都会抛出 `XlogKeySelectionException`，不作为可恢复提示继续成功。多个候选得到完全相同的内容时可以接受。原有 `privateKeyHex` 单密钥调用保留原先的恢复行为；两种参数一起提供时会合并并去重。

xlog 没有认证标签，原始 DEFLATE 也没有校验和，因此成功解压只能提供结构性验证，不能证明密钥身份或内容未被篡改。文件中的临时公钥无法直接指出应使用哪个服务端私钥。

候选共用单帧、单任务输出与 ECDH 缓存额度；`maxCachedKeys` 是所有候选派生密钥对共享的上限。任一候选触发输出或 Zstandard 窗口上限会立即失败，不会当作错误密钥跳过。流式接口仍逐块等待输出回调；致命错误前可能已经写出较早的有效帧，调用方必须丢弃整个临时结果。

## 服务端流式接口

`XlogDecoder.decodeTo` 接收 `Stream<List<int>>`，通过 `onData` 输出解码字节。输出回调返回 `Future` 时，解码器等待该次写入完成，再继续处理，调用方可据此实现背压。`onBlock` 与 `onIssue` 用于即时消费元数据；返回的 `XlogStreamSummary` 只保留摘要，不累计整个文件的块与提示列表。

以下示例位于调用方工程，因此可以使用 `dart:io`。私钥候选由后端配置提供，不能由 Web 前端持有或作为接口返回值。

```dart
import 'dart:io';

import 'package:xlog_decode/xlog_decode.dart';

Future<XlogStreamSummary> decodeFileOnServer({
  required String inputPath,
  required String temporaryOutputPath,
  required Iterable<String> privateKeysHex,
}) async {
  final output = await File(temporaryOutputPath).open(mode: FileMode.write);
  try {
    final decoder = XlogDecoder(privateKeysHex: privateKeysHex, strict: true);
    return await decoder.decodeTo(
      File(inputPath).openRead(),
      onData: (bytes) async {
        await output.writeFrom(bytes);
      },
    );
  } finally {
    await output.close();
  }
}
```

服务层应在成功后发布结果，失败或取消时删除临时输出。不要用不等待写入的无限缓冲队列承接 `onData`，也不要将所有输出拼成 `BytesBuilder` 后再保存。

`XlogStreamOptions` 控制以下独立上限：

| 选项 | 默认值 | 限制内容 |
| --- | --- | --- |
| `maxFrameBytes` | 1 MiB | 单个编码帧的大小，避免信任输入头声明而分配过大缓冲 |
| `maxDecodedBlockBytes` | 4 MiB | 单帧解码输出，约束压缩放大 |
| `maxInputChunkBytes` | 1 MiB | 每个输入流事件的字节数，调用方应提供有界输入块 |
| `outputChunkBytes` | 64 KiB | 每次输出回调的最大字节数 |
| `maxZstdWindowBytes` | 8 MiB | Zstandard 解压历史窗口 |
| `maxCachedKeys` | 16 项 | ECDH 派生密钥缓存项数 |

`XlogDecoder.maxOutputBytes` 另外约束一次任务的累计输出，默认为 128 MiB。库没有总输入量上限选项，服务端必须在上传或输入适配层另行限制总输入字节数。输入帧需要被完整验证后再处理，解密和解压仍会产生有界的单帧临时数据；这不是整个压缩算法的常量内存或零拷贝保证。调用方保留回调数据、输入源预先聚合完整文件、无界并发和 ZIP 适配器的聚合都可能重新扩大内存占用。

流式处理不自动提供多核并行，也不替代 HTTP 超时、上传限额、临时磁盘配额或任务取消。服务端应使用受限 Worker 池，逐条处理 ZIP，并按单任务峰值和运行时开销配置并发。服务端的任务处理和资源限制见 [服务端设计](../../docs/server-architecture.md)。

## 测试与示例

在本包目录执行，不需要 Flutter SDK：

```sh
dart pub get
dart analyze
dart test
dart run example/main.dart
```

本包提供可执行的服务端文件适配示例，用临时文件接收流式输出，成功后提交结果；已存在的输出文件会被拒绝：

```sh
dart run example/server_decode.dart input.xlog output.log
```

加密日志的 `XLOG_PRIVATE_KEY` 由服务端部署环境提供；不要把私钥写进前端配置。该示例是后端 Worker 的文件适配器，不是 HTTP 服务。

在两个独立进程中比较不同总输入量的内存观测值：

```sh
dart run benchmark/stream_memory.dart 16
dart run benchmark/stream_memory.dart 256
```

该脚本按需生成未加密帧并丢弃解码输出，报告解析缓冲峰值和包含 VM/JIT 的进程 RSS。它不测量解密、磁盘或网络吞吐，也不代表压缩最坏内存或生产并发；实际资源占用应使用目标日志和部署环境测量。

对照数据位于 `test/fixtures/`，覆盖原始 Mars C/TEA 向量和 Python 解码行为；测试数据中的私钥全部是公开样本，不用于生产。`test/fixtures/generators/` 只在重新生成对照数据时使用，日常运行和测试不需要 Python 或 Mars 源码。

`test/platform_compatibility_test.dart` 是可移植样本子集，可额外用 `dart test --platform chrome test/platform_compatibility_test.dart` 验证浏览器兼容性。这不改变 Web 产品由后端执行解密的架构。

Mars 适配代码的版权与依赖声明见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)。
