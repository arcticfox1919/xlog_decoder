import 'package:flutter/foundation.dart';

import '../../../core/xlog/xlog_decoder.dart';
import '../data/log_file_service.dart';
import '../domain/decode_models.dart';

class DecoderController extends ChangeNotifier {
  DecoderController({LogFileService service = const LocalLogFileService()})
    : _service = service;

  final LogFileService _service;
  final List<DecodeTask> _tasks = [];
  bool _busy = false;
  bool _disposed = false;
  int _nextId = 0;
  String? _outputDirectory;
  String? _configurationError;

  List<DecodeTask> get tasks => List.unmodifiable(_tasks);
  bool get busy => _busy;
  String? get outputDirectory => _outputDirectory;
  String? get configurationError => _configurationError;
  int get completedCount =>
      _tasks.where((task) => task.status == DecodeTaskStatus.success).length;

  void setOutputDirectory(String? directory) {
    if (_busy) return;
    _outputDirectory = directory;
    _notify();
  }

  void clear() {
    if (_busy) return;
    _tasks.clear();
    _configurationError = null;
    _notify();
  }

  Future<void> decodePaths(List<String> paths, {String? privateKeyHex}) async {
    if (_busy || paths.isEmpty) return;
    try {
      XlogDecoder(privateKeyHex: privateKeyHex);
    } on ArgumentError {
      _configurationError = '私钥需为有效的 64 位十六进制字符串；未加密日志可留空。';
      _notify();
      return;
    }
    _configurationError = null;
    _busy = true;
    final batch = [
      for (final path in paths.toSet())
        DecodeTask(id: _nextId++, inputPath: path),
    ];
    _tasks.insertAll(0, batch);
    _notify();
    try {
      for (final task in batch) {
        _replace(
          DecodeTask(
            id: task.id,
            inputPath: task.inputPath,
            status: DecodeTaskStatus.running,
          ),
        );
        try {
          final result = await _service.decode(
            DecodeRequest(
              inputPath: task.inputPath,
              outputDirectory: _outputDirectory,
              privateKeyHex: privateKeyHex?.trim(),
            ),
          );
          final status = result.successCount == 0
              ? DecodeTaskStatus.failure
              : result.hasWarnings
              ? DecodeTaskStatus.warning
              : DecodeTaskStatus.success;
          _replace(
            DecodeTask(
              id: task.id,
              inputPath: task.inputPath,
              status: status,
              result: result,
            ),
          );
        } on Exception catch (error) {
          _replace(
            DecodeTask(
              id: task.id,
              inputPath: task.inputPath,
              status: DecodeTaskStatus.failure,
              error: error is FormatException
                  ? error.message
                  : error.toString(),
            ),
          );
        }
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _replace(DecodeTask task) {
    _tasks[_tasks.indexWhere((entry) => entry.id == task.id)] = task;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
