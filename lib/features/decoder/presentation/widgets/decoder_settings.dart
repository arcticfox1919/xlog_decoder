import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

class DecoderSettings extends StatefulWidget {
  const DecoderSettings({
    super.key,
    required this.privateKeyController,
    required this.outputDirectory,
    required this.busy,
    required this.onSelectDirectory,
    required this.onResetDirectory,
    required this.onImportKey,
    this.error,
  });

  final TextEditingController privateKeyController;
  final String? outputDirectory;
  final bool busy;
  final VoidCallback onSelectDirectory;
  final VoidCallback onResetDirectory;
  final VoidCallback onImportKey;
  final String? error;

  @override
  State<DecoderSettings> createState() => _DecoderSettingsState();
}

class _DecoderSettingsState extends State<DecoderSettings> {
  bool _showKey = false;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: AppColors.muted),
            SizedBox(width: 7),
            Text(
              '解码设置',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Spacer(),
            Text(
              '自动保存',
              style: TextStyle(fontSize: 11, color: AppColors.faint),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          '输出目录',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 9),
        Tooltip(
          message: widget.outputDirectory ?? '点击选择输出目录',
          child: Material(
            color: AppColors.subtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              key: const Key('choose-output-directory'),
              borderRadius: BorderRadius.circular(9),
              onTap: widget.busy ? null : widget.onSelectDirectory,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_outlined,
                      size: 17,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.outputDirectory ?? '原文件所在目录',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: AppColors.faint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.outputDirectory != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.busy ? null : widget.onResetDirectory,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('恢复默认'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(height: 1),
        ),
        const Row(
          children: [
            Text(
              '解密私钥',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            SizedBox(width: 6),
            Text('可选', style: TextStyle(fontSize: 11, color: AppColors.faint)),
          ],
        ),
        const SizedBox(height: 9),
        TextField(
          key: const Key('private-key'),
          controller: widget.privateKeyController,
          enabled: !widget.busy,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: '64 位十六进制私钥',
            errorText: widget.error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _showKey ? '隐藏私钥' : '显示私钥',
              onPressed: widget.busy
                  ? null
                  : () => setState(() => _showKey = !_showKey),
              icon: Icon(
                _showKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 17,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        TextButton.icon(
          onPressed: widget.busy ? null : widget.onImportKey,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.file_open_outlined, size: 14),
          label: const Text('从文件导入私钥'),
        ),
        const SizedBox(height: 12),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 12,
                color: AppColors.faint,
              ),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '未加密日志可留空。私钥加密保存在本机，清空输入即可删除。',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
