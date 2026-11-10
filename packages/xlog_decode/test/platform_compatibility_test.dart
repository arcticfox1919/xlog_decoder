import 'dart:convert';

import 'package:test/test.dart';
import 'package:xlog_decode/xlog_decode.dart';

// Portable subset of fixtures/mars_reference.json. Kept inline because the
// existing fixture loader uses dart:io, which cannot run in browser tests.
const _privateKey =
    '030a11181f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dc';
const _frames = <String, String>{
  '07':
      'BwEACQqeAAAAxgR/lEHtfW0wRUBulcB82Fx3jkuM7zynq6wJuVxwnuUa4Wj+pj3DOaPFhBlGbOru9/YyZTJm0OEjZDGpUM/lKkZ8ob/a0t4KLeXi3OuO/POa3ZwXlDPftQl81waK0sjFJlQ+QJQU7AfBra141eUmPIfHP3i+9rkRaCNP4AKch0nOP0LrptoOWoIFgela0wefc/ph50dFUiUrKXNJXWjhtE9l2r7kwQSSiAKZy7Hs/+QDgmXi22a+inAPxe+AVRFzG1n5enyooUd2LYpETWwJPlPEtrH02vA6EgAAAP//AA==',
  '09':
      'CQEACQqeAAAAxgR/lEHtfW0wRUBulcB82Fx3jkuM7zynq6wJuVxwnuUa4Wj+pj3DOaPFhBlGbOru9/YyZTJm0OEjZDGpUM/lKor2jFXwTSwqVtC1U3BJLCqxUggNcdO1UHiyY+2zae06CoZmukX5pXkpCiGujjoKxSVFqYm5mXnpCsn5uQVFqcXFmfl5elzRo4aMGjJqyKgho4aMGjJqyKgho4aMGjJqyKgho4aMGjJqyKgho4aMGjIQhgAAAAD//+zMAQkAAACAoP+v2xHoACUSiUQikUgkEolEIpFIJJJvEgAAAP//AA==',
  '0c':
      'DAEACQpjAAAAxgR/lEHtfW0wRUBulcB82Fx3jkuM7zynq6wJuVxwnuUa4Wj+pj3DOaPFhBlGbOru9/YyZTJm0OEjZDGpUM/lKi5Tost6if47eogZbnUMd0r63O4XtWWNEYgUt68R5b8OyRwb6b1kVpA6nwZxRvR8utvJ1OpkbZK0Y6rpvQjFyv/FzXfytDCqR/uzoRb4vOlGmVHhKMWCxX05AV9wKdYNedIDIQA=',
  '0d':
      'DQEACQpjAAAAxgR/lEHtfW0wRUBulcB82Fx3jkuM7zynq6wJuVxwnuUa4Wj+pj3DOaPFhBlGbOru9/YyZTJm0OEjZDGpUM/lKii1L/0AMHwCAFQEW0ldIE1hcnMgLT4gRGFydDogVVRGLTgg5Lit5paHLCAxNi1yb3VuZCBURUEsIHN0cmVhbWluZyBjb21wcmVzc2lvbi4KAQCFpSB9iAJEAAAIWwEA2tIDIQA=',
};

void main() {
  final expected = utf8.encode(
    '[I] Mars -> Dart: UTF-8 中文, 16-round TEA, streaming compression.\n' * 140,
  );
  for (final entry in _frames.entries) {
    test('Mars ${entry.key} matches reference bytes on VM and browser', () {
      final result = XlogDecoder(
        privateKeyHex: _privateKey,
      ).decode(base64Decode(entry.value));
      expect(result.bytes, expected);
      expect(result.issues, isEmpty);
    });
  }
}
