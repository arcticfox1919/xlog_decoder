import 'server_configuration_exception.dart';

Map<String, Object?> configurationMap(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw ServerConfigurationException(field, 'expected a mapping');
  }
  return Map<String, Object?>.from(value);
}

void knownConfigurationFields(
  Map<String, Object?> values,
  Set<String> allowed,
  String field,
) {
  if (values.keys.any((key) => !allowed.contains(key))) {
    // Unknown names are user input too and may themselves contain a secret.
    throw ServerConfigurationException(field, 'contains an unknown field');
  }
}

String configurationString(
  Object? value,
  String field, {
  bool nonEmpty = false,
}) {
  if (value is! String || (nonEmpty && value.trim().isEmpty)) {
    throw ServerConfigurationException(
      field,
      'expected ${nonEmpty ? 'a nonempty' : 'a'} string',
    );
  }
  return value;
}
