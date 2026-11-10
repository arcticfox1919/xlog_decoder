import 'dart:convert';

/// Rewrites development-only URLs while retaining at most one URL's trailing
/// characters between input chunks. Uploads and downloads never enter here.
Stream<List<int>> redirectBootstrapUrls(
  Stream<List<int>> source,
  Map<String, String> replacements,
) => utf8.encoder.bind(_replace(utf8.decoder.bind(source), replacements));

Stream<String> _replace(
  Stream<String> source,
  Map<String, String> replacements,
) async* {
  final keep = replacements.keys.fold<int>(
    0,
    (length, key) => key.length > length ? key.length : length,
  );
  var pending = '';
  await for (final chunk in source) {
    pending += chunk;
    while (true) {
      String? match;
      var position = pending.length;
      for (final key in replacements.keys) {
        final index = pending.indexOf(key);
        if (index >= 0 && index < position) {
          match = key;
          position = index;
        }
      }
      if (match == null) break;
      yield pending.substring(0, position);
      yield replacements[match]!;
      pending = pending.substring(position + match.length);
    }
    if (pending.length > keep) {
      yield pending.substring(0, pending.length - keep);
      pending = pending.substring(pending.length - keep);
    }
  }
  if (pending.isNotEmpty) yield pending;
}
