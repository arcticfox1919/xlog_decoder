import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'features/decoder/data/native_preferences.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    // Wait for actual rasterization before revealing the native window.
    binding.waitUntilFirstFrameRasterized
        .then(
          (_) => const MethodChannel(
            'xlog/startup',
          ).invokeMethod<void>('firstFrameReady'),
        )
        .catchError((Object error) {
          debugPrint('Could not notify the macOS window: $error');
        });
  }
  runApp(XlogDecoderApp(preferences: createPreferencesStore()));
}
