import 'package:flutter/material.dart';

import '../application/decoder_controller.dart';
import '../data/file_dialog_service.dart';
import 'widgets/decode_task_list.dart';
import 'widgets/decoder_settings.dart';
import 'widgets/drop_zone.dart';

class DecoderPage extends StatefulWidget {
  const DecoderPage({
    super.key,
    this.controller,
    this.dialogs = const NativeFileDialogService(),
  });

  final DecoderController? controller;
  final FileDialogService dialogs;

  @override
  State<DecoderPage> createState() => _DecoderPageState();
}

class _DecoderPageState extends State<DecoderPage> {
  late final _controller = widget.controller ?? DecoderController();
  final _privateKey = TextEditingController();
  bool _dialogOpen = false;

  @override
  void dispose() {
    _privateKey.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _dialog(Future<void> Function() action) async {
    setState(() => _dialogOpen = true);
    try {
      await action();
    } on Exception catch (error) {
      _showError('无法打开文件选择窗口：$error');
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _selectFiles() => _dialog(() async {
    final paths = await widget.dialogs.selectLogs();
    if (mounted) await _decode(paths);
  });

  Future<void> _chooseDirectory() => _dialog(() async {
    final directory = await widget.dialogs.selectDirectory();
    if (directory != null && mounted) _controller.setOutputDirectory(directory);
  });

  Future<void> _importKey() => _dialog(() async {
    final key = await widget.dialogs.readPrivateKey();
    if (key != null && mounted) _privateKey.text = key.trim();
  });

  Future<void> _decode(List<String> paths) =>
      _controller.decodePaths(paths, privateKeyHex: _privateKey.text);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 850;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 20 : 40,
                vertical: 30,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context, compact),
                      const SizedBox(height: 36),
                      Text(
                        '让日志重新可读',
                        style: TextStyle(
                          fontSize: compact ? 28 : 34,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xff24283b),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '拖入日志文件或 ZIP，自动恢复并保存到本地。',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xff7b8296),
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (compact) ...[
                        _dropZone(),
                        const SizedBox(height: 20),
                        _settings(),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _dropZone()),
                            const SizedBox(width: 24),
                            SizedBox(width: 340, child: _settings()),
                          ],
                        ),
                      const SizedBox(height: 28),
                      DecodeTaskList(
                        tasks: _controller.tasks,
                        busy: _controller.busy,
                        onClear: _controller.clear,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '默认保存到输入文件同级目录  ·  同名输出自动编号  ·  全程本地处理',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff9299aa),
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _dropZone() => LogDropZone(
    busy: _controller.busy,
    dialogOpen: _dialogOpen,
    onFiles: _decode,
    onSelect: _selectFiles,
    onError: _showError,
  );

  Widget _settings() => DecoderSettings(
    privateKeyController: _privateKey,
    outputDirectory: _controller.outputDirectory,
    busy: _controller.busy || _dialogOpen,
    error: _controller.configurationError,
    onSelectDirectory: _chooseDirectory,
    onResetDirectory: () => _controller.setOutputDirectory(null),
    onImportKey: _importKey,
  );

  Widget _header(BuildContext context, bool compact) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(
          Icons.data_object_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
      const SizedBox(width: 13),
      const Text(
        'Xlog Decoder',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Color(0xff292e44),
        ),
      ),
      const Spacer(),
      if (!compact)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xffe8f3ed),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: Color(0xff43846a),
              ),
              SizedBox(width: 6),
              Text(
                '文件不离开你的设备',
                style: TextStyle(fontSize: 12, color: Color(0xff43846a)),
              ),
            ],
          ),
        ),
    ],
  );
}
