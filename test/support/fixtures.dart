import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final Map<String, dynamic> reference =
    jsonDecode(File('test/fixtures/mars_reference.json').readAsStringSync())
        as Map<String, dynamic>;

Uint8List unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

Uint8List modern(String magic) =>
    unhex((reference['modern'] as Map<String, dynamic>)[magic] as String);

Uint8List frame(
  int magic,
  List<int> payload, {
  int sequence = 0,
  int? headerSize,
}) {
  final size =
      headerSize ??
      (magic <= 2
          ? 5
          : magic <= 5
          ? 13
          : 73);
  final bytes = Uint8List(size + payload.length + 1);
  final view = ByteData.sublistView(bytes);
  bytes[0] = magic;
  view.setUint32(magic <= 2 ? 1 : 5, payload.length, Endian.little);
  if (magic > 2) view.setUint16(1, sequence, Endian.little);
  bytes.setRange(size, size + payload.length, payload);
  return bytes;
}
