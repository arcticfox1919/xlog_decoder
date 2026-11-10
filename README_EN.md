# Xlog Decoder

[简体中文](README.md) | **English**

Xlog Decoder converts Mars xlog files into readable text logs. It supports
encrypted logs, ZIP archives, batch processing, desktop and command-line use,
and a separate Jaspr Web frontend with an HTTP service.

## Downloads

Download the ZIP for your platform from [GitHub Releases](https://github.com/arcticfox1919/xlog_decoder/releases). Flutter is not required:

- **Windows x64:** Extract and run `XlogDecoder/xlog_decoder.exe`. Keep the DLLs and `data` directory beside it; the Visual C++ runtime is included.
- **macOS arm64:** For Apple Silicon (M-series Macs). Extract and move `XlogDecoder.app` to Applications. The app is ad-hoc signed and not notarized by Apple; if blocked on first launch, allow it in System Settings → Privacy & Security.

Development builds are available under **Actions → Desktop builds → a successful run → Artifacts** (GitHub login required, retained for 30 days). Extract the downloaded artifact to find the platform ZIP.

## Run the app

Install Flutter first. The Dart SDK version must satisfy the constraint in
`pubspec.yaml` (currently Dart 3.9.2 or newer, but below 4.0.0). From the project
directory, run:

```sh
flutter pub get
flutter run -d macos
```

Replace `macos` with `windows` or `linux` for the corresponding desktop target.

## Usage

1. **Enter the private key:** Leave it empty for unencrypted logs. For encrypted
   logs, enter the server private key or import it from a file.
2. **Add files:** Drop log files or ZIP archives onto the app, or use the file
   picker. Multiple files are supported and processing starts automatically.
3. **Review results:** The processing history shows output paths and failure
   details. By default, output is saved beside the input file. Click the output
   directory row to change it; the setting is remembered automatically.

For example, `app.xlog` produces `app.log`. If a file with the same name exists,
the desktop app uses `app1.log`, `app2.log`, and so on without overwriting it.

- ZIP archives process `.xlog`, `.log`, and `.bin` files, including files in
  subdirectories. Nested ZIP archives are not processed. Each archive is
  extracted into a folder named after the archive, such as `logs/`; existing
  folders are numbered as `logs1/`, `logs2/`, and so on. Nested directory names
  are flattened, and duplicate log names are numbered automatically.
- The private key must be 64 hexadecimal characters (32 bytes) and must match
  the public key used by the log writer. It is encrypted with Hive and stored
  locally; the key is restored automatically on the next launch. Clear the field
  to remove it. The encryption key is kept in the system secure storage.
- The macOS build disables the app sandbox, so dropped files can be saved beside
  the originals without first choosing an output directory.

## Interface languages

The language menu at the top right offers System default, 简体中文, and English. Changes take effect immediately and persist across restarts. The first launch follows the system language, falling back to English for unsupported languages.

Localization uses the [official Flutter approach](https://docs.flutter.dev/ui/internationalization): `flutter_localizations`, `intl`, ARB, and `gen-l10n`. Resources are in `lib/l10n/app_en.arb` and `app_zh.arb`, configured by `l10n.yaml`. Dynamic messages use ICU placeholders and plurals. Interface text and common operation errors are translated; raw technical diagnostics from the decoder, OS, and dependencies retain their original text. CLI messages and native application bundle names are unchanged.

To add a language, copy the English template to `app_<language_code>.arb`, translate every message, set `languageName` to its native name, and run `flutter gen-l10n`. The supported locales and language menu update automatically. Commit the regenerated `app_localizations*.dart` files with the ARB changes.

## Desktop and Web

The desktop client continues to read files, store private keys, and decode locally. The pure Dart package [`packages/xlog_decode`](packages/xlog_decode/README.md) supplies the shared decoder used by the desktop host and backend.

The Jaspr 0.23.5 frontend lives in [`packages/xlog_web`](packages/xlog_web/README.md); the HTTP backend lives in [`packages/xlog_server`](packages/xlog_server/README.md) and uses Shelf 1.4.3 with `shelf_router`. Shelf is maintained in the [official Dart repository](https://github.com/dart-lang/shelf) and powers the [`dart create -t server-shelf`](https://dart.dev/tools/dart-create) template. The browser uploads files, displays job status, and downloads results. Decoding, decryption, and private-key provisioning run on the backend. The Web project depends on neither Flutter nor the decoder library and has no private-key input. **No public deployment is configured.**

From the repository root, use a standalone Dart SDK 3.11 or newer, below 4.0, for the Web client and server:

```sh
dart scripts/web.dart

# Build only the frontend into packages/xlog_web/build/jaspr/
dart scripts/web.dart build

# Build the standalone AOT server; build-all builds both applications
dart scripts/web.dart build-server

# Configure a separate API origin when required by the deployment
dart scripts/web.dart build --api-url https://api.example.com/
```

The script installs dependencies, starts both services, and opens the browser. Press `Ctrl+C` to stop. Run `dart scripts/web.dart --help` for port and browser options.

Open the page and upload logs. The backend detects encrypted and unencrypted frames and automatically uses its configured keys; private keys stay on the backend. Development and production use same-origin `/api` requests by default. See the [Web guide](packages/xlog_web/README.md) and [binary deployment guide](docs/deployment.md).

The backend uses `decodeTo` with output backpressure and resource limits, writes uploads and results to temporary disk, and caps running jobs. Configure upload, disk, and concurrency budgets for the deployment; synthetic streaming benchmarks do not establish production capacity.

## Command-line usage

Run these commands from the project directory:

```sh
# Decode one file; writes app.log by default
dart run bin/decode_xlog.dart app.xlog

# Decode an encrypted log; key.txt contains only the hexadecimal private key
dart run bin/decode_xlog.dart --key-file key.txt app.xlog

# Specify the output file
dart run bin/decode_xlog.dart app.xlog decoded.log

# Process .xlog files directly inside a directory
dart run bin/decode_xlog.dart --key-file key.txt ./logs

# Show all options
dart run bin/decode_xlog.dart --help
```

The command-line tool overwrites existing output files. By default, it attempts
to continue when it encounters malformed content; use `--strict` to stop on the
first problem. Use `--legacy c` for legacy C-format logs.

## Use from Dart

```dart
import 'package:xlog_decode/xlog_decode.dart';

final decoder = XlogDecoder(privateKeyHex: serverPrivateKey); // Optional for unencrypted logs
final result = decoder.decode(bytes); // bytes is a Uint8List
print(result.text);
```

`result.bytes` contains the decoded raw bytes, and `result.issues` lists decoding
problems. This API retains the full input and output, so use it for the existing
desktop flow or size-limited inputs. A single decode produces at most 128 MiB by
default; adjust this with `maxOutputBytes` when needed. New server projects should
depend directly on `xlog_decode`. The original
`package:xlog_decoder/xlog_decoder.dart` entry point remains as a compatibility
re-export.

## Development and builds

```sh
flutter analyze
flutter test
flutter build windows --release
```

Replace `windows` with the target platform when building for macOS or Linux. The
decoder core is under `packages/xlog_decode/lib/src/`, and desktop features
are under `lib/features/decoder/`.

The core can be analyzed and tested separately with the same bundled Dart SDK:

```sh
cd packages/xlog_decode
dart pub get
dart analyze
dart test
```

Run both suites: root-level `flutter test` covers the client, while the package's
`dart test` covers parsing, cryptography, decompression, and reference fixtures.

The macOS build targets arm64 only and supports Apple Silicon (M-series Macs),
not Intel Macs. The distributed archive contains `XlogDecoder.app`; the UI is
named “Xlog 解码器”.

Build and package macOS in one step:

```sh
dart scripts/build_macos.dart
```

The script reads the version from `pubspec.yaml` and creates
`build/macos/dist/Xlog-Decoder-1.0.0-macOS-arm64.zip` (the filename changes with
the version). It automatically locates the Flutter SDK, or you can specify one:

```sh
FLUTTER_BIN=/path/to/flutter/bin/flutter dart scripts/build_macos.dart
```

The fixture-generation scripts in `packages/xlog_decode/test/fixtures/generators/` are only needed
when regenerating reference data. Python is not required to run, build, or test
the application.

### GitHub Actions builds

[desktop.yml](.github/workflows/desktop.yml) uses Flutter 3.35.7 as its CI build and validation baseline (local SDKs only need to satisfy the constraints in `pubspec.yaml`), runs analysis and tests for both the pure Dart core and the Flutter client, then builds Windows x64 and macOS arm64. Only pushes of `v*` tags and manual runs generate downloadable artifacts; branch pushes and PRs do not trigger builds. Manual runs only produce Actions artifacts; version tag pushes also publish a GitHub Release. To package Windows locally, run `dart scripts/build_windows.dart`; output is saved to `build/windows/dist/`.

To publish a release, update and commit the version in `pubspec.yaml`, then push a matching tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The tag must match `pubspec.yaml`. Once both builds succeed, the workflow creates a GitHub Release and uploads the ZIPs. Release notes are in English, with download and signing instructions and a link to the source commit. Tags with a prerelease suffix (such as `v1.0.1-beta.1`) create prereleases. It uses the built-in `GITHUB_TOKEN`; no additional secrets are required. The repository must allow Actions and workflows requesting `contents: write`. Windows code signing and Apple Developer ID signing/notarization are not configured.
