import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'decoder_settings.dart';
import 'decode_task_list.dart';
import '../../domain/decode_models.dart';
import '../../../../theme/app_theme.dart';

@Preview(name: '紧凑设置栏', size: Size(300, 480))
@Preview(name: '窄窗口设置栏', size: Size(420, 480))
Widget decoderSettingsPreview() => MaterialApp(
  theme: AppTheme.light,
  home: const Scaffold(body: SingleChildScrollView(child: _SettingsPreview())),
);

class _SettingsPreview extends StatefulWidget {
  const _SettingsPreview();

  @override
  State<_SettingsPreview> createState() => _SettingsPreviewState();
}

class _SettingsPreviewState extends State<_SettingsPreview> {
  final _key = TextEditingController();
  String? _directory;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoderSettings(
    privateKeyController: _key,
    outputDirectory: _directory,
    busy: false,
    onSelectDirectory: () => setState(() => _directory = '/Users/demo/Logs'),
    onResetDirectory: () => setState(() => _directory = null),
    onImportKey: () => _key.text = '0' * 63 + '1',
  );
}

@Preview(name: '处理记录与状态', size: Size(700, 500))
Widget decodeTaskStatesPreview() => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: DecodeTaskList(
        tasks: [
          DecodeTask(
            id: 0,
            inputPath: '/Logs/app.xlog',
            status: DecodeTaskStatus.success,
            result: DecodeBatchResult([
              const DecodedFile(
                sourceName: 'app.xlog',
                outputPath: '/Logs/app.log',
                byteCount: 24080,
                blockCount: 36,
              ),
            ]),
          ),
          const DecodeTask(
            id: 1,
            inputPath: '/Logs/broken.zip',
            status: DecodeTaskStatus.failure,
            error: '无法识别日志格式，请检查文件是否完整。',
          ),
        ],
        busy: false,
        onClear: previewClearTasks,
      ),
    ),
  ),
);

void previewClearTasks() {}
