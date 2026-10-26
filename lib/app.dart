import 'package:flutter/material.dart';

import 'features/decoder/presentation/decoder_page.dart';

class XlogDecoderApp extends StatelessWidget {
  const XlogDecoderApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Xlog Decoder',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff5349d8)),
      scaffoldBackgroundColor: const Color(0xfff5f6fa),
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const [
        'PingFang SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff7f8fc),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffe2e5ee)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xffeceef5)),
    ),
    home: home ?? const DecoderPage(),
  );
}
