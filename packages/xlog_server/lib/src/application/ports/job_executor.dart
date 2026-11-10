import '../../domain/decode_result.dart';
import '../../domain/decode_task.dart';

abstract interface class JobExecutor {
  Future<DecodeResult> execute(DecodeTask task);
}
