import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

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
    final active = _hovering && !widget.busy;
    return DropTarget(
      enable: !widget.busy && !widget.dialogOpen,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _drop,
      child: Container(
        key: const Key('log-drop-zone'),
        padding: const EdgeInsets.all(16),
        decoration: panelDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 16,
                  color: AppColors.muted,
                ),
                SizedBox(width: 7),
                Text(
                  '添加日志',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Spacer(),
                Text(
                  '支持多选',
                  style: TextStyle(fontSize: 11, color: AppColors.faint),
                ),
              ],
            ),
            const SizedBox(height: 14),
            CustomPaint(
              foregroundPainter: _DropOutline(
                active ? AppColors.accent : const Color(0xffd8dfe6),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: active ? AppColors.accentSoft : AppColors.subtle,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: active ? 1.08 : 1,
                      duration: const Duration(milliseconds: 160),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x080f172a),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: widget.busy
                            ? const Padding(
                                padding: EdgeInsets.all(15),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                active
                                    ? Icons.file_download_outlined
                                    : Icons.upload_file_outlined,
                                size: 27,
                                color: AppColors.accent,
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.busy
                          ? '正在解码日志…'
                          : active
                          ? '松开，开始解码'
                          : '拖入日志或 ZIP',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.busy ? '完成后可在下方查看结果' : '自动解压、解密，生成可读日志',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('select-files'),
                      onPressed: widget.busy || widget.dialogOpen
                          ? null
                          : widget.onSelect,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('选择文件'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '.xlog   ·   .log   ·   .bin   ·   .zip',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.faint,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropOutline extends CustomPainter {
  const _DropOutline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(11)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 9) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 4, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DropOutline oldDelegate) => oldDelegate.color != color;
}
