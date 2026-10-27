import 'package:flutter/widgets.dart';

import 'app.dart';
import 'features/decoder/data/native_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(XlogDecoderApp(preferences: createPreferencesStore()));
}
