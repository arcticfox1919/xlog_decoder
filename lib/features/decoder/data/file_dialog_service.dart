import 'package:file_selector/file_selector.dart';

abstract interface class FileDialogService {
  Future<List<String>> selectLogs();
  Future<String?> selectDirectory();
  Future<String?> readPrivateKey();
}

class NativeFileDialogService implements FileDialogService {
  const NativeFileDialogService({
    this.logFilesLabel = 'Logs or ZIP',
    this.allFilesLabel = 'All files',
    this.directoryButtonLabel = 'Set output directory',
  });

  final String logFilesLabel;
  final String allFilesLabel;
  final String directoryButtonLabel;

  @override
  Future<List<String>> selectLogs() async => [
    for (final file in await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: logFilesLabel,
          extensions: ['xlog', 'log', 'bin', 'zip'],
        ),
        XTypeGroup(label: allFilesLabel),
      ],
    ))
      file.path,
  ];

  @override
  Future<String?> selectDirectory() =>
      getDirectoryPath(confirmButtonText: directoryButtonLabel);

  @override
  Future<String?> readPrivateKey() async => (await openFile())?.readAsString();
}
