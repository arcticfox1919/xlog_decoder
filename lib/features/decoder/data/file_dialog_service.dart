import 'package:file_selector/file_selector.dart';

abstract interface class FileDialogService {
  Future<List<String>> selectLogs();
  Future<String?> selectDirectory();
  Future<String?> readPrivateKey();
}

class NativeFileDialogService implements FileDialogService {
  const NativeFileDialogService();

  @override
  Future<List<String>> selectLogs() async => [
    for (final file in await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: '日志或 ZIP', extensions: ['xlog', 'log', 'bin', 'zip']),
        XTypeGroup(label: '所有文件'),
      ],
    ))
      file.path,
  ];

  @override
  Future<String?> selectDirectory() =>
      getDirectoryPath(confirmButtonText: '设为输出目录');

  @override
  Future<String?> readPrivateKey() async => (await openFile())?.readAsString();
}
