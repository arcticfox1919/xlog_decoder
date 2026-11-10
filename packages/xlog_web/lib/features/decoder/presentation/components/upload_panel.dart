import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

import '../../../../browser/browser_upload_file.dart';
import '../../../../l10n/strings.dart';
import '../../domain/decoder_api.dart';

class UploadPanel extends StatefulComponent {
  const UploadPanel({
    super.key,
    required this.strings,
    required this.enabled,
    required this.uploading,
    required this.onFiles,
  });

  final Strings strings;
  final bool enabled;
  final bool uploading;
  final ValueChanged<List<UploadFile>> onFiles;

  @override
  State<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<UploadPanel> {
  bool _hovering = false;

  @override
  void didUpdateComponent(covariant UploadPanel oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.uploading) _hovering = false;
  }

  void _submitFiles(List<web.File> files) {
    setState(() => _hovering = false);
    component.onFiles(files.map(BrowserUploadFile.new).toList());
  }

  @override
  Component build(BuildContext context) =>
      section(classes: 'panel upload-panel', [
        div(classes: 'panel-heading', [
          h2([Component.text(component.strings.text('addLogs'))]),
          small([Component.text(component.strings.text('multiple'))]),
        ]),
        div(
          classes: 'drop-zone',
          attributes: {'data-active': '$_hovering'},
          events: {
            'dragover': (event) {
              event.preventDefault();
              if (component.enabled && !component.uploading && !_hovering) {
                setState(() => _hovering = true);
              }
            },
            'dragleave': (_) => setState(() => _hovering = false),
            'drop': (event) {
              event.preventDefault();
              final dropped = (event as dynamic) as web.DragEvent;
              final files = dropped.dataTransfer?.files;
              setState(() => _hovering = false);
              if (component.enabled && !component.uploading && files != null) {
                _submitFiles([
                  for (var i = 0; i < files.length; i++) files.item(i)!,
                ]);
              }
            },
          },
          [
            div(
              classes: 'drop-icon',
              attributes: {'aria-hidden': 'true'},
              [Component.text('↑')],
            ),
            h2([
              Component.text(
                component.strings.text(
                  component.uploading
                      ? 'uploading'
                      : _hovering
                      ? 'dropActive'
                      : 'dropTitle',
                ),
              ),
            ]),
            p(classes: 'helper', [
              Component.text(component.strings.text('dropHint')),
            ]),
            input<List<web.File>>(
              type: InputType.file,
              id: 'log-files',
              classes: 'file-input',
              disabled: !component.enabled || component.uploading,
              attributes: {'multiple': '', 'accept': '.xlog,.log,.bin,.zip'},
              onChange: (files) {
                if (component.enabled && !component.uploading) {
                  _submitFiles(files);
                }
                final element =
                    web.document.getElementById('log-files')
                        as web.HTMLInputElement?;
                if (element != null) element.value = '';
              },
            ),
            label(
              htmlFor: 'log-files',
              classes: 'primary-button',
              attributes: {
                'aria-disabled': '${!component.enabled || component.uploading}',
              },
              [Component.text(component.strings.text('selectFiles'))],
            ),
            p(classes: 'file-types', [
              Component.text('.xlog  ·  .log  ·  .bin  ·  .zip'),
            ]),
          ],
        ),
      ]);
}
