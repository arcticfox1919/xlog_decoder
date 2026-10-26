# xlog_decoder

Flutter 桌面 GUI 日志解码工具，支持拖拽或选择日志/ZIP，自动解压、解密、解码并生成可读的 `.txt.log` 文件。
解码核心以 `mars/xlog/crypt/decode_mars_crypt_log_file.py` 和 `decode_mars_nocrypt_log_file.py` 为主要行为依据，C 实现及 C 样本用于交叉验证。

## 桌面界面

```powershell
flutter pub get
flutter run -d windows
# 发布构建
flutter build windows --release
```

1. 加密日志先填写服务器私钥，或点击「从文件导入私钥」；未加密日志可留空。
2. 如需改变输出位置，点击「选择目录」；「恢复默认」回到输入文件所在目录。
3. 将日志文件或 ZIP 拖入卡片，或点击「选择文件」，选定后自动处理。也支持一次选择多个文件。
4. 展开处理记录可查看输出路径、复制路径及失败原因；ZIP 中的单个日志失败不会中断其他日志。

输出规则：

- `app.xlog` → 同级 `app.txt.log`；ZIP 默认也输出到 ZIP 所在目录。
- ZIP 中识别 `.xlog`、`.log`、`.bin` 文件，包含子目录；跳过其他文件、目录和符号链接，不递归处理 ZIP 中的 ZIP。
- ZIP 日志直接在内存中解压后解码，不向磁盘解出中间文件；输出文件名取日志 basename，统一放在输出目录。
- 同名输出自动编号：`app.txt.log`、`app (1).txt.log`，不覆盖已有文件或输入文件。
- 私钥仅保留在当前界面的内存中，不写入磁盘。文件解压、解码和写出在后台 isolate 中完成。

GUI 面向 Windows/macOS/Linux 桌面；当前在 Windows 环境构建验证。macOS 保留应用沙箱并启用用户选择文件的读写权限；若输入文件同级目录不在授权范围内，请通过「选择目录」授权输出目录。

## 依赖与职责

| 依赖 | 用途 |
| --- | --- |
| [pointycastle](https://pub.dev/packages/pointycastle) | secp256k1 公钥解析、ECDH 共享密钥计算 |
| [archive](https://pub.dev/packages/archive) | 纯 Dart raw DEFLATE 流式解压、Zstandard 解压 |
| [args](https://pub.dev/packages/args) | CLI 参数解析、帮助信息、参数校验 |
| [desktop_drop](https://pub.dev/packages/desktop_drop/versions/0.8.4) | 桌面文件拖拽、拖入区域状态、macOS 拖入文件访问 |
| [file_selector](https://pub.dev/packages/file_selector) | 系统文件、输出目录及私钥文件选择 |
| [path](https://pub.dev/packages/path) | 跨平台路径和输出文件名处理 |

只手写 xlog 特有的帧格式、旧版分块/XOR、16 轮小端 TEA，以及未结束压缩流的适配。
Mars 的 TEA 不能直接替换成标准的 32 轮 TEA 或 XXTEA。

## 作为库使用

```dart
import 'dart:typed_data';
import 'package:xlog_decoder/xlog_decoder.dart';

XlogDecodeResult decodeLog(Uint8List bytes, String? serverPrivateKey) {
  return XlogDecoder(
    privateKeyHex: serverPrivateKey,
    // false：记录问题后尝试恢复后续块；true：遇到问题就抛异常。
    strict: false,
    maxOutputBytes: 128 * 1024 * 1024,
  ).decode(bytes);
}
```

`result.bytes` 是原始日志字节；`result.text` 以 UTF-8 显示，替换非法字符。
`result.blocks` 包含成功解码块的偏移、标记、序号、小时和长度；`result.issues` 包含帧错误、序号缺失、解密或解压失败。
诊断信息独立保存，不插入日志正文。每次调用独立跟踪序号和缓存 ECDH 密钥。

加密异步块需要与写入端服务器公钥配对的 **32 字节私钥（64 个十六进制字符）**。
文件中保存的是客户端临时公钥，不能据此恢复服务器私钥。实现不内置源码脚本中的示例私钥。

协议核心是同步的，字节及输出驻留内存；GUI 的文件处理服务已在 isolate 中调用它。
`maxOutputBytes` 限制单次累计输出，默认 128 MiB；这不是进程总内存上限。

## 命令行

在本项目目录运行：

```powershell
flutter pub get

# 未加密文件，默认输出为 app.txt.log。
dart run bin/decode_xlog.dart app.xlog

# 加密文件，key.txt 只包含十六进制私钥；也可以使用 XLOG_PRIVATE_KEY 环境变量。
dart run bin/decode_xlog.dart --key-file key.txt app.xlog decoded.log

# 批量处理目录中的 .xlog 文件，不递归；序号状态按文件重置。
dart run bin/decode_xlog.dart --key-file key.txt ./logs

# C 解码器的历史头布局与 XOR；现代格式不受该选项影响。
dart run bin/decode_xlog.dart --legacy c old.xlog

dart run bin/decode_xlog.dart --strict app.xlog
dart run bin/decode_xlog.dart --help
```

输出文件若已存在会覆盖，但禁止覆盖输入文件本身。有问题时尽量保留成功解码的日志并返回退出码 `1`；参数错误返回 `64`。
严格模式失败、没有可解码块时，不写输出。

## 格式兼容

默认假定写入端为小端，与仓库脚本在常见 x86/ARM 平台的行为一致。

| 标记 | 行为 |
| --- | --- |
| `0x06 / 0x08 / 0x0a / 0x0b` | 同步明文，直接复制；`CryptSyncLog` 的加密代码已注释 |
| `0x07` | secp256k1 ECDH → 共享密钥前 16 字节 → 16 轮 TEA → raw DEFLATE |
| `0x09` | raw DEFLATE |
| `0x0c` | secp256k1 ECDH → 共享密钥前 16 字节 → 16 轮 TEA → Zstandard |
| `0x0d` | Zstandard |
| `0x01 / 0x02`，选择 `c` | C 实现的旧版 XOR / XOR + DEFLATE，5 字节头；Python 默认模式不识别 |
| `0x03–0x05`，默认 `python` | Python 脚本的 13 字节头，分别为明文、DEFLATE、分块合并 + DEFLATE |
| `0x03–0x05`，选择 `c` | C 脚本的 9 字节头，增加序号派生 XOR；`0x05` 先合并分块 |

默认采用 Python 脚本的格式范围、头布局和载荷处理分支。C 历史格式作为显式兼容选项保留，使用时指定 `legacyFormat: XlogLegacyFormat.c`。
`0x05` 的分块长度是小端 `uint16`；合并后的数据是同一条压缩流。

异步写入只执行 `Z_SYNC_FLUSH` / `ZSTD_e_flush`，文件中可能没有压缩流结束标记。
适配层补上空结束块后交给三方库解压。Zstd 只接受完整块边界上的未结束流，且要求没有声明内容长度、没有校验和；其他截断报告错误。
TEA 每 8 字节独立处理，末尾不足 8 字节原样保留；ECDH 的 X 坐标保留前导零。

初次定位按照 Python 的 `GetLogStartPos(buffer, 2)` 校验相邻两块；单块恰好到文件末尾也接受。进入解码流程后，损坏处按照 `GetLogStartPos(buffer, 1)` 搜索下一块，载荷解码失败则跳过该块并继续。raw DEFLATE 空输入返回空字节，与 Python 的 `decompressobj` 一致。

保留的 Dart API 差异：错误信息独立保存为结构化结果；空载荷帧按实际头、长度与尾标记校验；尾部 mmap 零填充可忽略；首次定位前跳过的数据也会记录诊断。私钥由调用方提供，序号按文件重置，不内置原脚本的示例密钥。

## 模块组织

```text
lib/main.dart               Flutter 入口
lib/app.dart                MaterialApp、主题与首页
lib/xlog_decoder.dart        协议核心的兼容导出（CLI/测试可继续使用）
lib/core/xlog/
  models.dart               配置枚举、结果、元数据、诊断和异常
  format.dart               各 magic 的压缩、加密、头布局定义
  frame.dart                帧边界和头字段解析、字节视图
  cipher.dart               私钥校验、ECDH、TEA、会话内密钥缓存
  compression.dart          三方解压入口和 xlog 流结束适配
  payload_decoder.dart      旧版变换 → 解密 → 解压
  xlog_decoder.dart         扫描、恢复、序号跟踪、输出预算
lib/features/decoder/
  domain/decode_models.dart  文件请求、输出结果、任务状态
  data/log_file_service.dart 后台 isolate、ZIP、文件读写、输出命名
  data/file_dialog_service.dart 系统文件/目录选择接口
  application/decoder_controller.dart 任务状态、配置校验、顺序处理
  presentation/decoder_page.dart 页面编排与交互
  presentation/widgets/     拖拽卡片、解码设置、处理记录
bin/decode_xlog.dart         可选命令行入口
```

新增格式时，在 `format.dart` 定义其行为；新增算法时，在对应解密或压缩模块扩展。
文件读写不进入协议核心，核心测试直接输入字节即可。界面通过可替换服务接口测试文件选择和后台任务，文件服务用临时目录验证完整解码输出。

## 验证

```powershell
flutter analyze
flutter test
```

`test/fixtures/python_reference.json` 是直接执行仓库 Python 原脚本函数得到的对照结果，覆盖加密脚本与无加密脚本支持的载荷分支，以及首次定位/损坏恢复的搜索规则。
生成器只适配 Python 2 语法、字节操作及已变化的三方库接口，`DecodeBuffer`、TEA、`GetLogStartPos` 等逻辑来自原文件。样本记录原脚本 SHA-256，便于识别参考版本。

重新生成 Python 对照样本需要 Python 3.9/3.10、`cryptography` 和 `zstandard`：

```powershell
python -m pip install cryptography zstandard
python tool/generate_python_fixtures.py --mars-root ../path/to/mars
```

日常 Dart 测试只读取固定 JSON，不依赖 Python 或 C 编译环境。

`test/fixtures/mars_reference.json` 是补充的 C 对照样本。
样本由仓库原有 `uECC.c`、zlib、zstd 和 Mars 的 TEA 加密算法生成，覆盖现代全部标记、两次 flush 的未结束压缩流、中文、TEA 所有尾部长度及 ECDH 前导零。
测试中的私钥仅为公开测试数据。历史格式、损坏恢复、序号、输出预算另有单独测试。

若需要重新生成样本，在 Windows 配置好 Clang 后执行：

```powershell
./tool/generate_reference_fixtures.ps1 -Compiler clang -MarsRoot ../path/to/mars
```

默认 Mars 路径匹配当前并列仓库目录。生成器只用于测试，不是运行时依赖。
另外已将加密 zlib/Zstd 的 C 样本编译为 JavaScript 并在 Node.js 中校验，以验证 Web 下的整数运算兼容性。
