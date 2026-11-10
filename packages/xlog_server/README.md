# Xlog Server

需要独立 Dart SDK 3.11 或以上、低于 4.0.0。

提供日志上传、解码任务查询和结果下载。服务端自动识别日志帧的加密、压缩类型；未加密内容直接解码，加密内容使用后端配置的密钥自动解密。

## 开发运行

在仓库根目录执行：

```sh
dart scripts/web.dart
```

脚本启动前后端并打开 `http://localhost:18780`。页面直接使用，浏览器请求的 `/api` 由开发代理转发到后端；按 `Ctrl+C` 停止。

## 编译与运行二进制

```sh
dart scripts/web.dart build-server
./build/server/xlog_server --config /path/server.yaml
```

Windows 产物为 `build/server/xlog_server.exe`。这是当前系统和架构的 AOT 可执行文件，运行时不需要安装 Dart 或 Flutter。配置、私钥文件和日志数据单独部署。

`build` 只打包前端，`build-all` 同时构建前端和服务端。部署方式见 [部署说明](../../docs/deployment.md)。

## 配置

复制 [server.example.yaml](server.example.yaml) 为 `server.yaml`，按需修改：

```sh
# 一键开发
dart scripts/web.dart --config packages/xlog_server/server.yaml

# 在 packages/xlog_server 中单独启动后端
dart run bin/server.dart --config server.yaml
```

也可用 `XLOG_CONFIG_FILE` 指定文件。环境变量覆盖 YAML，未配置的字段使用默认值；`--config` 优先于 `XLOG_CONFIG_FILE`。YAML 相对路径以文件所在目录为准，修改后重启生效。

| 环境变量 | 用途 |
| --- | --- |
| `HOST` / `PORT` | 后端监听地址，默认 `127.0.0.1:18781` |
| `XLOG_CONFIG_FILE` | YAML 配置文件 |
| `XLOG_KEYS_FILE` | 密钥 JSON 文件；也可用 YAML 的 `keys` 字段 |
| `XLOG_DATA_DIR` | 上传与结果目录 |
| `XLOG_WEB_ROOT` | 可选的前端静态目录 |
| `XLOG_ALLOWED_ORIGINS` | 单独跨域部署时允许的前端来源 |

密钥文件格式：

```json
{"device-a":{"label":"设备 A","privateKeyHex":"<64个十六进制字符>"}}
```

配置、私钥和日志数据留在服务端，数据目录不能与前端目录重合或互相包含。一键开发模式自动管理本机监听地址、端口和代理。

配置多把密钥时，后端会按每个加密帧尝试候选密钥，支持同一文件或 ZIP 中混合不同密钥及未加密日志。未配置密钥仍可处理未加密日志；遇到缺钥、密钥不匹配或解密结果不确定时，整个任务失败并清理部分输出，避免漏掉加密内容。

默认同时解码 2 个任务、等待额度 4 个，上传请求也占额度；满额返回 `429`。单上传最多 256 MiB、单任务输出最多 128 MiB，结果保留 1 小时。调整方法见 [服务端设计](../../docs/server-architecture.md#资源配置)。

## API

| 操作 | 接口 |
| --- | --- |
| 状态与限额 | `GET /api/health` |
| 上传原始文件字节 | `POST /api/jobs?filename=...` |
| 查询任务 | `GET /api/jobs/{id}` |
| 删除排队或已完成任务 | `DELETE /api/jobs/{id}` |
| 下载结果 | `GET /api/jobs/{id}/download` |

支持 `.xlog`、`.log`、`.bin` 和标准 ZIP。上传只需文件名和原始文件字节，创建成功返回 `202`；任务完成后使用返回的 `downloadUrl` 下载。结果随任务删除或过期失效。

## 运行日志

使用 Dart 官方 `logging` 包，输出英文 JSON 日志，包含请求 ID、任务 ID、耗时、处理结果和异常堆栈，不记录私钥、日志正文或上传文件名。请求耗时统计到响应头生成，不包含下载传输时间。

默认级别为 `INFO`；设置 `XLOG_LOG_LEVEL=FINE` 可查看健康检查和任务轮询请求。响应头 `X-Request-ID` 可用于定位请求。普通日志输出到 stdout，警告和错误输出到 stderr，可交给部署工具收集并轮转。
