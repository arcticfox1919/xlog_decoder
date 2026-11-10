# Development and build commands

Web and server commands require Dart >=3.11.0 <4.0.0.

Run from the repository root with your standalone Dart SDK:

```sh
dart scripts/web.dart                   # Develop at http://localhost:18780/
dart scripts/web.dart --no-open         # Keep the browser closed
dart scripts/web.dart --config packages/xlog_server/server.yaml
dart scripts/web.dart build             # Web assets only
dart scripts/web.dart build-server      # Native standalone backend
dart scripts/web.dart build-all         # Web assets, then native backend
```

The script uses the same Dart executable for all child processes. Dependency resolution preserves compatible locked versions but can adapt SDK-specific build tools when switching Dart versions.

Web output: `packages/xlog_web/build/jaspr/`. Server output: `build/server/xlog_server` (`.exe` on Windows). The executable targets the build machine's operating system and architecture. Run it with `--config /path/server.yaml`.

Development exposes one origin on port 18780. `/api` requests stream to the backend on port 18781; other requests and hot reload connections stream to private Jaspr and webdev ports, selected automatically. Development bootstrap URLs are rewritten as a bounded stream to keep reload connections on the public origin. Use `--web-port` and `--server-port` to change the public and backend ports. Press Ctrl+C to stop owned services.

Build commands do not load runtime server configuration or pass server settings to the frontend. `build` and `build-all` accept `--api-url https://api.example.com/` for separate deployments; otherwise the frontend uses its own origin.

`web.dart` parses options and starts `WebRunner`. `src/development_command.dart` owns development startup and the gateway; `src/build_command.dart` owns build steps. `src/process_support.dart` handles SDK selection, child processes, readiness and shutdown. `src/dev_gateway.dart` handles streaming HTTP forwarding; `api_upload_tunnel.dart` is limited to development API requests with bodies and returns early backend rejections without waiting for the upload to finish; `web_socket_relay.dart` owns WebSocket shutdown and `bootstrap_urls.dart` rewrites development URLs. Port and argument validation live in their own files.

## Desktop packaging

Run `dart scripts/build_windows.dart` on Windows or `dart scripts/build_macos.dart` on macOS, using the Dart bundled with Flutter. Both scripts share version parsing, Flutter discovery and process helpers in `src/desktop_build_support.dart`. Windows packages include the Visual C++ runtime DLLs; macOS packages retain native signing and archive tools.
