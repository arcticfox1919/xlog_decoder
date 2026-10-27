import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/decode_models.dart';
import '../../../../theme/app_theme.dart';

class DecodeTaskList extends StatelessWidget {
  const DecodeTaskList({
    super.key,
    required this.tasks,
    required this.busy,
    required this.onClear,
  });

  final List<DecodeTask> tasks;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            '处理记录',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                '${tasks.length} 个任务',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: busy || tasks.isEmpty ? null : onClear,
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            child: const Text('清空记录'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (tasks.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          decoration: panelDecoration(),
          child: const Column(
            children: [
              Icon(Icons.inbox_outlined, size: 28, color: AppColors.faint),
              SizedBox(height: 12),
              Text(
                '还没有处理记录',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '生成 .log 日志，ZIP 结果保存到独立文件夹',
                style: TextStyle(fontSize: 11, color: AppColors.faint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      for (final task in tasks)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TaskCard(
            key: ValueKey('${task.id}-${task.status.name}'),
            task: task,
          ),
        ),
    ],
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({super.key, required this.task});
  final DecodeTask task;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (task.status) {
      DecodeTaskStatus.queued => (
        '等待中',
        AppColors.faint,
        Icons.schedule_rounded,
      ),
      DecodeTaskStatus.running => ('处理中', AppColors.accent, Icons.sync_rounded),
      DecodeTaskStatus.success => (
        '已完成',
        AppColors.accent,
        Icons.check_circle_outline_rounded,
      ),
      DecodeTaskStatus.warning => (
        '部分恢复',
        AppColors.warning,
        Icons.warning_amber_rounded,
      ),
      DecodeTaskStatus.failure => (
        '未完成',
        AppColors.danger,
        Icons.error_outline_rounded,
      ),
    };
    final result = task.result;
    return Container(
      decoration: panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded:
            task.status == DecodeTaskStatus.failure ||
            task.status == DecodeTaskStatus.warning,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            p.extension(task.inputPath).toLowerCase() == '.zip'
                ? Icons.folder_zip_outlined
                : Icons.description_outlined,
            size: 19,
            color: color,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                p.basename(task.inputPath),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(
            result == null
                ? task.inputPath
                : '已生成 ${result.successCount} 个日志'
                      '${result.failureCount > 0 ? ' · ${result.failureCount} 个失败' : ''}'
                      '${result.skippedEntries > 0 ? ' · 跳过 ${result.skippedEntries} 个非日志条目' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        children: [
          const Divider(),
          if (task.error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                task.error!,
                style: const TextStyle(color: AppColors.danger, height: 1.6),
              ),
            ),
          for (final file in result?.files ?? <DecodedFile>[])
            _OutputFile(file: file),
        ],
      ),
    );
  }
}

class _OutputFile extends StatelessWidget {
  const _OutputFile({required this.file});
  final DecodedFile file;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          file.sourceName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 5),
        if (file.outputPath != null)
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  file.outputPath!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.accent,
                    height: 1.6,
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制输出路径',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: file.outputPath!),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已复制输出路径')));
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            ],
          ),
        if (file.succeeded)
          Text(
            '${file.blockCount} 个日志块 · ${_size(file.byteCount)}',
            style: const TextStyle(fontSize: 12, color: AppColors.faint),
          ),
        if (file.error != null)
          SelectableText(
            file.error!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.7,
            ),
          ),
        if (file.issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              '恢复提示（${file.issues.length}）\n${file.issues.join('\n')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.warning,
                height: 1.6,
              ),
            ),
          ),
      ],
    ),
  );
}

String _size(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
