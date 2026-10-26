import 'package:xlog_decoder/features/decoder/data/log_file_service.dart';
import 'package:xlog_decoder/features/decoder/domain/decode_models.dart';

DecodeBatchResult successfulBatch() => DecodeBatchResult([
  const DecodedFile(
    sourceName: 'a.xlog',
    outputPath: 'a.txt.log',
    byteCount: 100,
    blockCount: 1,
  ),
]);

class FakeLogFileService implements LogFileService {
  FakeLogFileService({this.handler});
  final Future<DecodeBatchResult> Function(DecodeRequest)? handler;
  final List<DecodeRequest> requests = [];

  @override
  Future<DecodeBatchResult> decode(DecodeRequest request) {
    requests.add(request);
    return handler?.call(request) ?? Future.value(successfulBatch());
  }
}
