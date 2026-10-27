import 'package:flutter/material.dart';

import 'features/decoder/presentation/decoder_page.dart';
import 'features/decoder/data/decoder_preferences.dart';
import 'theme/app_theme.dart';

class XlogDecoderApp extends StatelessWidget {
  const XlogDecoderApp({super.key, this.home, this.preferences});

  final Widget? home;
  final DecoderPreferencesStore? preferences;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Xlog 解码器',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: home ?? DecoderPage(preferences: preferences),
  );
}
