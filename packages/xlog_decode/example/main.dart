import 'dart:convert';
import 'dart:typed_data';

import 'package:xlog_decode/xlog_decode.dart';

void main() {
  // An unencrypted 0x08 frame. Applications supply real log bytes through
  // their own file or upload adapters, and provision keys outside this library.
  final payload = utf8.encode('Hello from Mars xlog!\n');
  final input = Uint8List(73 + payload.length + 1);
  input[0] = 0x08;
  ByteData.sublistView(input).setUint32(5, payload.length, Endian.little);
  input.setRange(73, 73 + payload.length, payload);

  final result = XlogDecoder(strict: true).decode(input);
  print(result.text);
}
