import 'configuration_fields.dart';
import 'server_configuration_exception.dart';

class ConfigurationValues {
  ConfigurationValues(this.environment, this.yaml);
  final Map<String, String> environment;
  final Map<String, Object?> yaml;

  String? string(String env, String field, {String? fallback}) {
    final value = environment[env] ?? yaml[field] ?? fallback;
    if (value == null) return null;
    return configurationString(
      value,
      environment.containsKey(env) ? env : field,
      nonEmpty: true,
    );
  }

  int integer(
    String env,
    String field,
    int fallback, {
    int minimum = 1,
    int? maximum,
    bool limit = false,
  }) {
    final label = environment.containsKey(env) ? env : field;
    final source = limit
        ? (yaml['limits'] as Map<String, Object?>? ?? {})[field]
        : yaml[field];
    final value = environment.containsKey(env)
        ? int.tryParse(environment[env]!)
        : source ?? fallback;
    if (value is! int ||
        value < minimum ||
        (maximum != null && value > maximum)) {
      throw ServerConfigurationException(
        environment.containsKey(env) || !limit ? label : 'limits.$field',
        'expected an integer within the permitted range',
      );
    }
    return value;
  }

  int limit(String env, String field, int fallback, {int minimum = 1}) =>
      integer(env, field, fallback, minimum: minimum, limit: true);

  Duration seconds(String env, String field, int fallback) => Duration(
    seconds: integer(env, field, fallback, maximum: 9223372036854, limit: true),
  );

  Set<String> get origins {
    final value = environment['XLOG_ALLOWED_ORIGINS'];
    if (value != null) {
      return value
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    final yamlOrigins = yaml['allowedOrigins'];
    if (yamlOrigins != null) return (yamlOrigins as List<String>).toSet();
    return const {'http://localhost:18780', 'http://127.0.0.1:18780'};
  }
}
