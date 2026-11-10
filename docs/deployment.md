# Web 与服务端部署

构建需要独立 Dart SDK >=3.11、低于 4.0。部署后的服务端二进制无需安装 Dart 或 Flutter。

## 构建

在仓库根目录执行：

```sh
dart scripts/web.dart build-all
```

产物：

- `packages/xlog_web/build/jaspr/`：前端静态文件。
- `build/server/xlog_server`：服务端二进制，Windows 带 `.exe`。

二进制对应构建机器的系统和架构，应在与部署目标匹配的环境中构建。

## 配置与启动

参考 [server.example.yaml](../packages/xlog_server/server.example.yaml) 创建配置，填写监听地址、数据目录和解密密钥。密钥只配置在后端。

```sh
./xlog_server --config /srv/xlog/server.yaml
```

前端默认访问当前站点的 `/api`。下面两种方式任选其一。

## 方式一：服务端同时提供页面

将前端产物复制到 `/srv/xlog/web`，在配置中加入：

```yaml
host: 0.0.0.0
port: 18781
webRoot: /srv/xlog/web
dataDirectory: /srv/xlog/data
```

启动后访问 `http://服务器地址:18781`。配置、密钥和数据目录必须放在前端目录之外。

## 方式二：使用 Nginx

将前端产物复制到 `/srv/xlog/web`，后端监听 `127.0.0.1:18781`。Nginx 提供页面并转发 API 请求：

```nginx
server {
    listen 80;
    server_name _;
    root /srv/xlog/web;
    client_max_body_size 256m;

    location /api/ {
        proxy_pass http://127.0.0.1:18781;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

若调整后端上传上限，也应同步调整 Nginx 的 `client_max_body_size`。

如果页面和 API 必须使用不同域名，构建时通过 `--api-url` 指定 API 地址，并在后端 `allowedOrigins` 中填写页面来源，详见 [Web 说明](../packages/xlog_web/README.md#构建与部署)。
