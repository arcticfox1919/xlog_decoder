import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/app.dart';

void main() {
  testWidgets('Shows the decoder workspace', (tester) async {
    await tester.pumpWidget(const XlogDecoderApp());
    expect(find.text('Xlog Decoder'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.text('原文件所在目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
