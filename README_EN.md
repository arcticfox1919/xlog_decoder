# Xlog Decoder

Xlog Decoder converts Mars xlog files into readable text logs. It supports
encrypted logs, ZIP archives, batch processing, and both desktop and command-line use.

中文文档：[README.md](README.md)

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
import 'package:xlog_decoder/xlog_decoder.dart';

final decoder = XlogDecoder(privateKeyHex: serverPrivateKey); // Optional for unencrypted logs
final result = decoder.decode(bytes); // bytes is a Uint8List
print(result.text);
```

`result.bytes` contains the decoded raw bytes, and `result.issues` lists decoding
problems. A single decode produces at most 128 MiB by default; adjust this with
`maxOutputBytes` when needed.

## Development and builds

```sh
flutter analyze
flutter test
flutter build windows --release
```

Replace `windows` with the target platform when building for macOS or Linux. The
decoder core is under `lib/core/xlog/`, and desktop features are under
`lib/features/decoder/`.

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

The fixture-generation scripts in `test/fixtures/generators/` are only needed
when regenerating reference data. Python is not required to run, build, or test
the application.
