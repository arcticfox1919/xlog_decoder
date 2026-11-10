import 'server_config.dart';

/// Process launch options; application services do not read environment state.
class ServerOptions {
  const ServerOptions({
    required this.config,
    this.host = '127.0.0.1',
    this.port = 18781,
  });

  final ServerConfig config;
  final String host;
  final int port;
}
