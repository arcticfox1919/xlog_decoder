import 'dart:io';

import 'package:test/test.dart';

import '../../../scripts/src/port_check.dart';

void main() {
  test(
    'selects distinct ephemeral internal ports and releases reservations',
    () async {
      final first = await findAvailablePort();
      final second = await findAvailablePort(excluding: {first});
      expect(second, isNot(first));
      final listeners = await Future.wait([
        ServerSocket.bind(InternetAddress.loopbackIPv4, first),
        ServerSocket.bind(InternetAddress.loopbackIPv4, second),
      ]);
      for (final listener in listeners) {
        await listener.close();
      }
    },
  );
  for (final address in [
    InternetAddress.loopbackIPv4,
    InternetAddress.anyIPv4,
  ]) {
    test('rejects a port occupied on ${address.address}', () async {
      final listener = await ServerSocket.bind(address, 0);
      final subscription = listener.listen((socket) => socket.destroy());
      addTearDown(() async {
        await subscription.cancel();
        await listener.close();
      });
      await expectLater(
        checkAvailablePort(listener.port),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already in use'),
          ),
        ),
      );
    });
  }

  test('accepts a free port and leaves it available for the service', () async {
    final reservation = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = reservation.port;
    await reservation.close();
    await checkAvailablePort(port);
    final listener = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    await listener.close();
  });
}
