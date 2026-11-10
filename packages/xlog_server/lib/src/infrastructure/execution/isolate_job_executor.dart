import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../application/ports/job_executor.dart';
import '../../domain/decode_result.dart';
import '../../domain/decode_task.dart';
import 'log_file_decoder.dart';
import 'output_filename.dart';
import 'zip_job_decoder.dart';

class IsolateJobExecutor implements JobExecutor {
  const IsolateJobExecutor();

  @override
  Future<DecodeResult> execute(DecodeTask task) {
    // Only immutable scalar task data crosses the isolate boundary.
    final workspacePath = task.workspacePath;
    final name = task.name;
    final privateKeysHex = task.privateKeysHex;
    final maxOutputBytes = task.maxOutputBytes;
    return Isolate.run(
      () => _decode(workspacePath, name, privateKeysHex, maxOutputBytes),
    );
  }
}

Future<DecodeResult> _decode(
  String workspacePath,
  String name,
  List<String> privateKeysHex,
  int maxOutputBytes,
) async {
  if (p.extension(name).toLowerCase() == '.zip') {
    return const ZipJobDecoder().decode(
      DecodeTask(
        workspacePath: workspacePath,
        name: name,
        privateKeysHex: privateKeysHex,
        maxOutputBytes: maxOutputBytes,
      ),
    );
  }
  final filename = '${outputStem(name, maxLength: null)}.log';
  final summary = await const LogFileDecoder().decode(
    input: File(p.join(workspacePath, 'input')),
    output: File(p.join(workspacePath, filename)),
    maxOutputBytes: maxOutputBytes,
    privateKeysHex: privateKeysHex,
  );
  return DecodeResult(
    filename: filename,
    outputBytes: summary.outputBytes,
    blockCount: summary.blockCount,
    issueCount: summary.issueCount,
  );
}
