import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class LogDropZone extends StatefulWidget {
  const LogDropZone({
    super.key,
    required this.busy,
    required this.onFiles,
    required this.onSelect,
    required this.onError,
    this.dialogOpen = false,
  });

  final bool busy;
  final bool dialogOpen;
  final Future<void> Function(List<String>) onFiles;
  final VoidCallback onSelect;
  final ValueChanged<String> onError;

  @override
  State<LogDropZone> createState() => _LogDropZoneState();
}

class _LogDropZoneState extends State<LogDropZone> {
  bool _hovering = false;

  Future<void> _drop(DropDoneDetails details) async {
    setState(() => _hovering = false);
    final files = details.files.whereType<DropItemFile>().toList();
    if (files.isEmpty) {
      widget.onError('请拖入日志文件或 ZIP 文件，不支持直接拖入文件夹。');
      return;
    }
    final access = <DropItemFile>[];
    try {
      for (final file in files) {
        final bookmark = file.extraAppleBookmark;
        if (bookmark != null &&
            bookmark.isNotEmpty &&
            await DesktopDrop.instance.startAccessingSecurityScopedResource(
              bookmark: bookmark,
            )) {
          access.add(file);
        }
      }
      await widget.onFiles(files.map((file) => file.path).toList());
    } on Exception catch (error) {
      widget.onError('无法读取拖入的文件：$error');
    } finally {
      for (final file in access) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: file.extraAppleBookmark!,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return DropTarget(
      enable: !widget.busy && !widget.dialogOpen,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _drop,
      child: AnimatedContainer(
        key: const Key('log-drop-zone'),
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 440),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
        decoration: BoxDecoration(
          color: _hovering ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _hovering ? color : const Color(0xffdcdfee),
            width: _hovering ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: widget.busy
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Icon(
                      _hovering
                          ? Icons.file_download_rounded
                          : Icons.file_present_rounded,
                      size: 38,
                      color: color,
                    ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.busy
                  ? '正在恢复日志…'
                  : _hovering
                  ? '松开文件，开始解码'
                  : '拖拽日志或 ZIP 到这里',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              widget.busy ? '文件正在后台处理，完成后会显示输出位置' : '松开即自动解压、解密和解码',
              style: const TextStyle(color: Color(0xff73798c), height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('select-files'),
              onPressed: widget.busy || widget.dialogOpen
                  ? null
                  : widget.onSelect,
              icon: const Icon(Icons.folder_open_rounded, size: 20),
              label: const Text('选择文件'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '单个日志  /  日志 ZIP  /  支持多选',
              style: TextStyle(fontSize: 12, color: Color(0xff8b90a1)),
            ),
          ],
        ),
      ),
    );
  }
}
