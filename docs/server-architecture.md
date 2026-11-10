# 服务端设计

服务端接收日志，将解码结果保存到磁盘，供浏览器下载。启动与接口见 [服务端说明](../packages/xlog_server/README.md)。

## 分层与依赖

`packages/xlog_server/lib/src` 的主要目录：

| 目录 | 职责 |
| --- | --- |
| `domain/` | 任务、结果、状态和错误类型 |
| `application/` | 上传接收、任务排队、并发控制和清理 |
| `application/ports/` | 存储和解码执行接口，方便替换实现与测试 |
| `infrastructure/storage/` | 文件读写和静态资源读取 |
| `infrastructure/execution/` | 调用解码库、处理 ZIP、在独立 isolate 中执行任务 |
| `http/` | 路由、JSON 响应、跨域和错误处理 |
| `configuration/` | YAML、环境变量和配置校验 |
| `server.dart` | 组装服务、启动监听和关闭清理 |

HTTP 层调用应用层，应用层通过接口使用存储和解码能力。日志格式解析、解密和解压统一交给 `xlog_decode`。

## 任务处理

1. 上传内容分块写入任务目录，不将整个文件放进内存。
2. 上传完成后排队，有空闲额度时启动独立解码任务。
3. 从磁盘读取日志，逐块解码并写出结果。ZIP 内的日志逐个处理。
4. 完成后删除上传原文件，保留结果供流式下载。
5. 任务删除或结果过期后清理文件；已开始的下载读完后再回收。

服务端按日志块标志识别加密与压缩类型：未加密直接解码，加密则自动尝试后端配置的密钥。同一文件或 ZIP 可以包含不同密钥的日志。缺少密钥、无法匹配或结果有歧义时，整个任务失败并清理部分结果。

排队任务可以取消；上传中、运行中的任务暂不支持取消。重复上传目前会创建新任务，不复用之前的结果。

## 资源配置

配置优先级：环境变量 > YAML > 默认值。YAML 相对路径以配置文件所在目录为准，修改后需重启。完整示例见 [server.example.yaml](../packages/xlog_server/server.example.yaml)。

以下字段放在 YAML 的 `limits` 下：

| 字段 | 环境变量 | 默认值 |
| --- | --- | --- |
| `maxConcurrentJobs` | `XLOG_CONCURRENCY` | 同时解码 2 个任务 |
| `maxQueuedJobs` | `XLOG_MAX_QUEUED` | 等待额度 4 个，上传也占额度 |
| `maxRetainedJobs` | `XLOG_MAX_JOBS` | 最多保留 64 个任务 |
| `maxUploadBytes` | `XLOG_MAX_UPLOAD_BYTES` | 单文件 256 MiB |
| `maxOutputBytes` | `XLOG_MAX_OUTPUT_BYTES` | 单任务输出 128 MiB |
| `jobTtlSeconds` | `XLOG_JOB_TTL_SECONDS` | 完成结果保留 3600 秒 |
| `uploadTimeoutSeconds` | `XLOG_UPLOAD_TIMEOUT_SECONDS` | 上传空闲超时 600 秒 |

上传与输出主要占用磁盘；内存用于有上限的日志块缓冲、解压窗口和任务状态。并发越高，CPU 与内存开销越大，应根据实际日志和机器配置调整。

ZIP 不支持 ZIP64 或嵌套压缩包；最多 128 个条目，单条目展开上限 256 MiB，总展开上限 512 MiB。ZIP 内全部日志共用单任务输出限额。

## 部署时需要了解

- 队列和任务记录只保存在当前进程，重启后不恢复；异常退出留下的文件需另行清理。
- 当前为单实例服务，多实例不能直接共用任务目录。
- 密钥和数据目录与前端静态目录分开，私钥不发送到浏览器。
- 下载后结果仍会保留到过期或被删除，需为结果和临时文件预留磁盘空间。

## 开发检查

在 `packages/xlog_server` 下执行：

```sh
dart pub get
dart analyze
dart test
```
