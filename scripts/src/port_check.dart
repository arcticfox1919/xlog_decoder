import 'dart:io';

/// Picks an ephemeral loopback port, excluding other ports in this launch.
/// The actual child bind still reports any race with another process.
Future<int> findAvailablePort({Set<int> excluding = const {}}) async {
  while (true) {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    if (!excluding.contains(port)) return port;
  }
}

/// A loopback bind alone can miss an existing wildcard listener on platforms
/// that permit address reuse, so check for listeners before trying to bind.
Future<void> checkAvailablePort(int port) async {
  StateError unavailable() => StateError(
    'Port $port is unavailable (already in use or permission denied). '
    'Choose another port with --web-port or --server-port.',
  );
  Socket? existing;
  try {
    existing = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
  } on SocketException {
    // Also check bind permission and non-listening reservations below.
  }
  if (existing != null) {
    existing.destroy();
    throw unavailable();
  }
  try {
    final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    await socket.close();
  } on SocketException {
    throw unavailable();
  }
}
