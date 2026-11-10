import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final Map<String, dynamic> reference =
    jsonDecode(
          File(
            'packages/xlog_decode/test/fixtures/mars_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Uint8List unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

Uint8List modern(String magic) =>
    unhex((reference['modern'] as Map<String, dynamic>)[magic] as String);
