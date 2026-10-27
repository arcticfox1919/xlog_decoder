import 'package:flutter/material.dart';

import '../../../core/xlog/xlog_decoder.dart';
import '../../../theme/app_theme.dart';
import '../application/decoder_controller.dart';
import '../data/decoder_preferences.dart';
import '../data/file_dialog_service.dart';
import 'widgets/decode_task_list.dart';
import 'widgets/decoder_settings.dart';
import 'widgets/drop_zone.dart';

class DecoderPage extends StatefulWidget {
  const DecoderPage({
    super.key,
    this.controller,
    this.dialogs = const NativeFileDialogService(),
    this.preferences,
  });

  final DecoderController? controller;
  final FileDialogService dialogs;
  final DecoderPreferencesStore? preferences;

  @override
  State<DecoderPage> createState() => _DecoderPageState();
}

class _DecoderPageState extends State<DecoderPage> {
  late final _controller = widget.controller ?? DecoderController();
  final _privateKey = TextEditingController();
  bool _dialogOpen = false;
  bool _loadingSettings = false;
  String _lastPrivateKey = '';
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _loadingSettings = widget.preferences != null;
    _privateKey.addListener(_privateKeyChanged);
    // Show the workspace before invoking file-system and Keychain plugins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPreferences();
    });
  }

  Future<void> _loadPreferences() async {
    final store = widget.preferences;
    if (store == null) return;
    try {
      final saved = await store.load();
      if (!mounted) return;
      _controller.setOutputDirectory(saved.outputDirectory);
      _lastPrivateKey = saved.privateKeyHex ?? '';
      _privateKey.text = _lastPrivateKey;
    } catch (_) {
      if (mounted) {
        _showError('无法读取已保存的设置，请重新选择目录或输入私钥。');
      }
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _persist(Future<void> Function() action) {
    _pendingSave = _pendingSave.then((_) => action()).catchError((Object _) {
      _showError('设置保存失败，本次修改未保存，请检查本机存储权限。');
    });
    return _pendingSave;
  }

  void _privateKeyChanged() {
    final value = _privateKey.text.trim();
    if (_loadingSettings || value == _lastPrivateKey) return;
    try {
      XlogDecoder(privateKeyHex: value);
    } on ArgumentError {
      return; // Persist only complete valid keys, or an explicit clear.
    }
    _lastPrivateKey = value;
    final store = widget.preferences;
    if (store != null) _persist(() => store.savePrivateKey(value));
  }

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

  Future<void> _selectFiles() async {
    List<String> paths = [];
    await _dialog(() async {
      paths = await widget.dialogs.selectLogs();
    });
    if (mounted) await _decode(paths);
  }

  Future<void> _chooseDirectory() => _dialog(() async {
    final directory = await widget.dialogs.selectDirectory();
    if (directory != null && mounted) {
      _controller.setOutputDirectory(directory);
      final store = widget.preferences;
      if (store != null) {
        await _persist(() => store.saveOutputDirectory(directory));
      }
    }
  });

  Future<void> _resetDirectory() async {
    _controller.setOutputDirectory(null);
    final store = widget.preferences;
    if (store != null) await _persist(() => store.saveOutputDirectory(null));
  }

  Future<void> _importKey() => _dialog(() async {
    final key = await widget.dialogs.readPrivateKey();
    if (key != null && mounted) _privateKey.text = key.trim();
  });

  Future<void> _decode(List<String> paths) async {
    if (paths.isEmpty || _controller.busy || _dialogOpen || _loadingSettings) {
      return;
    }
    await _controller.decodePaths(paths, privateKeyHex: _privateKey.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 24,
                vertical: 28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context, compact),
                      const SizedBox(height: 24),
                      if (compact) ...[
                        _dropZone(),
                        const SizedBox(height: 20),
                        _settings(),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _dropZone()),
                            const SizedBox(width: 16),
                            SizedBox(width: 300, child: _settings()),
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
                        '全程本地处理  ·  保留原文件  ·  同名自动编号',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.faint,
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
    dialogOpen: _dialogOpen || _loadingSettings,
    onFiles: _decode,
    onSelect: _selectFiles,
    onError: _showError,
  );

  Widget _settings() => DecoderSettings(
    privateKeyController: _privateKey,
    outputDirectory: _controller.outputDirectory,
    busy: _controller.busy || _dialogOpen || _loadingSettings,
    error: _controller.configurationError,
    onSelectDirectory: _chooseDirectory,
    onResetDirectory: _resetDirectory,
    onImportKey: _importKey,
  );

  Widget _header(BuildContext context, bool compact) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff248b77), Color(0xff225f60)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x16000000)),
        ),
        child: const Icon(
          Icons.terminal_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xlog 解码器',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Narwal 日志解码工具',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
      if (!compact)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xffdbebe3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 13, color: AppColors.accent),
              SizedBox(width: 6),
              Text(
                '本地处理',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
