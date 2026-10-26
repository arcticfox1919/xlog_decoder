import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/decode_models.dart';

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
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          if (tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                '${tasks.length} 个任务',
                style: const TextStyle(fontSize: 13, color: Color(0xff818799)),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: busy || tasks.isEmpty ? null : onClear,
            child: const Text('清空记录'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (tasks.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(34),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 30,
                color: Color(0xffb1b7c8),
              ),
              SizedBox(height: 12),
              Text('还没有处理记录', style: TextStyle(color: Color(0xff787f92))),
              SizedBox(height: 6),
              Text(
                '生成的可读日志以 .txt.log 结尾',
                style: TextStyle(fontSize: 12, color: Color(0xffa0a6b6)),
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
        const Color(0xff8b90a1),
        Icons.schedule_rounded,
      ),
      DecodeTaskStatus.running => (
        '处理中',
        const Color(0xff5349d8),
        Icons.sync_rounded,
      ),
      DecodeTaskStatus.success => (
        '已完成',
        const Color(0xff16856a),
        Icons.check_circle_outline_rounded,
      ),
      DecodeTaskStatus.warning => (
        '部分恢复',
        const Color(0xffb77912),
        Icons.warning_amber_rounded,
      ),
      DecodeTaskStatus.failure => (
        '未完成',
        const Color(0xffc34f54),
        Icons.error_outline_rounded,
      ),
    };
    final result = task.result;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded:
            task.status == DecodeTaskStatus.failure ||
            task.status == DecodeTaskStatus.warning,
        tilePadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
        leading: Icon(
          p.extension(task.inputPath).toLowerCase() == '.zip'
              ? Icons.folder_zip_outlined
              : Icons.description_outlined,
          color: color,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                p.basename(task.inputPath),
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
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
            style: const TextStyle(fontSize: 12, color: Color(0xff818799)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        children: [
          const Divider(),
          if (task.error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                task.error!,
                style: const TextStyle(color: Color(0xffc34f54), height: 1.6),
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
                    color: Color(0xff16856a),
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
            style: const TextStyle(fontSize: 12, color: Color(0xff8b90a1)),
          ),
        if (file.error != null)
          SelectableText(
            file.error!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xffc34f54),
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
                color: Color(0xffb77912),
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
