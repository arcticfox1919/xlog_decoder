import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
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
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: AppColors.muted),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                AppLocalizations.of(context).decoderSettings,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context).autoSave,
              style: TextStyle(fontSize: 11, color: AppColors.faint),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context).outputDirectory,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 9),
        Tooltip(
          message:
              widget.outputDirectory ??
              AppLocalizations.of(context).chooseOutputDirectory,
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
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
                        widget.outputDirectory ??
                            AppLocalizations.of(context).sourceDirectory,
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
              child: Text(AppLocalizations.of(context).resetDirectory),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(height: 1),
        ),
        Row(
          children: [
            Text(
              AppLocalizations.of(context).privateKey,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            SizedBox(width: 6),
            Text(
              AppLocalizations.of(context).optional,
              style: TextStyle(fontSize: 11, color: AppColors.faint),
            ),
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
            hintText: AppLocalizations.of(context).privateKeyHint,
            errorText: widget.error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _showKey
                  ? AppLocalizations.of(context).hidePrivateKey
                  : AppLocalizations.of(context).showPrivateKey,
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
          label: Text(AppLocalizations.of(context).importPrivateKey),
        ),
        const SizedBox(height: 12),
        Row(
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
                AppLocalizations.of(context).privateKeyHelp,
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
