/// A field-level diagnostic safe for CLI output. Never stores source values,
/// filenames, parser excerpts, or private keys.
class ServerConfigurationException extends ArgumentError {
  ServerConfigurationException(this.field, this.problem)
    : super('Invalid $field: $problem.');

  final String field;
  final String problem;

  @override
  String toString() => message as String;
}
