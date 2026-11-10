import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../l10n/app_localizations.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/decode_models.dart';
import '../decode_failure_text.dart';

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
          Expanded(
            child: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context).processingHistory,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (tasks.isNotEmpty)
                  Text(
                    AppLocalizations.of(context).taskCount(tasks.length),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy || tasks.isEmpty ? null : onClear,
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            child: Text(AppLocalizations.of(context).clearHistory),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (tasks.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          decoration: panelDecoration(),
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 28, color: AppColors.faint),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).noHistory,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
              SizedBox(height: 6),
              Text(
                AppLocalizations.of(context).outputHelp,
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
        AppLocalizations.of(context).statusQueued,
        AppColors.faint,
        Icons.schedule_rounded,
      ),
      DecodeTaskStatus.running => (
        AppLocalizations.of(context).statusRunning,
        AppColors.accent,
        Icons.sync_rounded,
      ),
      DecodeTaskStatus.success => (
        AppLocalizations.of(context).statusSuccess,
        AppColors.accent,
        Icons.check_circle_outline_rounded,
      ),
      DecodeTaskStatus.warning => (
        AppLocalizations.of(context).statusWarning,
        AppColors.warning,
        Icons.warning_amber_rounded,
      ),
      DecodeTaskStatus.failure => (
        AppLocalizations.of(context).statusFailure,
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
        title: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              p.basename(task.inputPath),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
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
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
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
                : [
                    AppLocalizations.of(
                      context,
                    ).generatedLogs(result.successCount),
                    if (result.failureCount > 0)
                      AppLocalizations.of(
                        context,
                      ).failedLogs(result.failureCount),
                    if (result.skippedEntries > 0)
                      AppLocalizations.of(
                        context,
                      ).skippedEntries(result.skippedEntries),
                  ].join(' · '),
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
                task.failure == null
                    ? task.error!
                    : decodeFailureText(
                        AppLocalizations.of(context),
                        task.failure!,
                      ),
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
                tooltip: AppLocalizations.of(context).copyOutputPath,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: file.outputPath!),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context).outputPathCopied,
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
            ],
          ),
        if (file.succeeded)
          Text(
            '${AppLocalizations.of(context).logBlocks(file.blockCount)} · ${_size(file.byteCount)}',
            style: const TextStyle(fontSize: 12, color: AppColors.faint),
          ),
        if (file.error != null)
          SelectableText(
            file.failure == null
                ? file.error!
                : decodeFailureText(
                    AppLocalizations.of(context),
                    file.failure!,
                  ),
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
              AppLocalizations.of(
                context,
              ).recoveryHints(file.issues.length, file.issues.join('\n')),
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
