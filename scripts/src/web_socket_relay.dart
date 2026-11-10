import 'dart:async';
import 'dart:io';

/// Owns both stream subscriptions so shutdown can finish addStream before
/// closing a WebSocket sink. Closing a bound sink directly throws in dart:io.
class WebSocketRelay {
  WebSocketRelay(this.first, this.second) {
    _forward = _RelayDirection(first, second);
    _reverse = _RelayDirection(second, first);
    done = Future.any([_forward.done, _reverse.done]);
  }

  final WebSocket first;
  final WebSocket second;
  late final _RelayDirection _forward;
  late final _RelayDirection _reverse;
  late final Future<void> done;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await Future.wait([_forward.stop(), _reverse.stop()]);
    await Future.wait([first.close(), second.close()]);
  }
}

class _RelayDirection {
  _RelayDirection(WebSocket source, WebSocket destination) {
    _subscription = source.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: _controller.close,
    );
    _controller
      ..onPause = _subscription.pause
      ..onResume = _subscription.resume
      ..onCancel = _subscription.cancel;
    done = destination.addStream(_controller.stream);
  }

  final _controller = StreamController<dynamic>(sync: true);
  late final StreamSubscription<dynamic> _subscription;
  late final Future<void> done;

  Future<void> stop() async {
    await _subscription.cancel();
    await _controller.close();
    try {
      await done;
    } catch (_) {
      // A peer disconnect is a normal relay shutdown.
    }
  }
}
