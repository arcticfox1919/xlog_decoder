import 'package:flutter/material.dart';

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
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '解码设置',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        const Text('输出目录', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xfff5f6fa),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 19,
                color: Color(0xff72798e),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.outputDirectory ?? '原文件所在目录',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            TextButton(
              key: const Key('choose-output-directory'),
              onPressed: widget.busy ? null : widget.onSelectDirectory,
              child: const Text('选择目录'),
            ),
            if (widget.outputDirectory != null)
              TextButton(
                onPressed: widget.busy ? null : widget.onResetDirectory,
                child: const Text('恢复默认'),
              ),
          ],
        ),
        const Divider(height: 24),
        const Text('解密私钥（可选）', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          key: const Key('private-key'),
          controller: widget.privateKeyController,
          enabled: !widget.busy,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: '64 位十六进制私钥',
            hintStyle: const TextStyle(fontSize: 13),
            errorText: widget.error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _showKey ? '隐藏私钥' : '显示私钥',
              onPressed: () => setState(() => _showKey = !_showKey),
              icon: Icon(
                _showKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: widget.busy ? null : widget.onImportKey,
          icon: const Icon(Icons.key_rounded, size: 17),
          label: const Text('从文件导入私钥'),
        ),
        const SizedBox(height: 10),
        const Text(
          '未加密的日志无需填写。私钥仅用于本次会话，不保存到磁盘。',
          style: TextStyle(fontSize: 12, color: Color(0xff858b9b), height: 1.7),
        ),
      ],
    ),
  );
}
