/// Web-only copy. No Flutter runtime or decoder/private-key dependency.
class Strings {
  const Strings(this.locale);
  final String locale;
  static const languages = {'zh': '简中', 'en': 'English'};
  String text(String key) =>
      _messages[locale]?[key] ?? _messages['en']![key] ?? key;

  String status(String status) => text('status_$status');
  String error(String code) => text('error_$code') == 'error_$code'
      ? text('error_unknown')
      : text('error_$code');

  static const _messages = {
    'zh': {
      'title': 'Xlog 解码器',
      'subtitle': 'Narwal 日志解码工具 · Web',
      'serverProcessing': '服务端解码',
      'language': '界面语言',
      'addLogs': '添加日志',
      'multiple': '支持多选',
      'dropTitle': '拖入日志或 ZIP',
      'dropActive': '松开，上传日志',
      'dropHint': '上传至解码服务，下载可读日志',
      'selectFiles': '选择文件',
      'uploading': '正在上传…',
      'decodeNotice': '解码说明',
      'automaticDecryption': '解密密钥由后端配置，系统自动识别日志并完成解码或解密。',
      'preparing': '正在准备解码服务…',
      'retry': '重试',
      'serviceUnavailable': '解码服务暂不可用，请稍后重试。',
      'history': '处理记录',
      'clear': '清空记录',
      'empty': '还没有处理记录',
      'emptyHint': '选择日志后自动上传，处理完成后下载结果',
      'download': '下载日志',
      'cancel': '取消任务',
      'privacy': '日志上传至解码服务  ·  私钥保留在服务端  ·  保留本机原文件',
      'limits': '单文件上传上限',
      'fileTooLarge': '文件超过服务允许的上传大小。',
      'historyFull': '处理记录已满，请等待当前任务完成后清空记录。',
      'status_uploading': '上传中',
      'status_queued': '等待中',
      'status_running': '处理中',
      'status_success': '已完成',
      'status_warning': '部分恢复',
      'status_failure': '未完成',
      'status_cancelled': '已取消',
      'blocks': '日志块',
      'notes': '恢复提示',
      'error_network': '解码服务暂不可用，请检查网络或稍后重试。',
      'error_forbidden': '无权执行此操作。',
      'error_queue_full': '服务繁忙，请稍后重试。',
      'error_upload_too_large': '上传文件超过服务限额。',
      'error_invalid_input': '未恢复到日志，请检查文件格式。',
      'error_decode_failed': '日志处理失败，请检查日志文件。',
      'error_resource_limit': '任务超过服务的资源限额。',
      'error_not_found': '任务已过期或不存在，请重新上传。',
      'error_not_cancellable': '任务正在处理，暂时无法取消。',
      'error_unsupported_file': '不支持此文件格式。',
      'error_unknown': '操作失败，请稍后重试。',
    },
    'en': {
      'title': 'Xlog Decoder',
      'subtitle': 'Narwal log decoding tool · Web',
      'serverProcessing': 'Server processing',
      'language': 'Language',
      'addLogs': 'Add logs',
      'multiple': 'Multiple files',
      'dropTitle': 'Drop logs or ZIP files',
      'dropActive': 'Release to upload',
      'dropHint': 'Upload to your service, then download readable logs',
      'selectFiles': 'Select files',
      'uploading': 'Uploading…',
      'decodeNotice': 'About decoding',
      'automaticDecryption':
          'Decryption keys are configured on the backend. The system automatically detects the logs and decodes or decrypts them.',
      'preparing': 'Preparing the decoder…',
      'retry': 'Retry',
      'serviceUnavailable':
          'The decoder is unavailable. Please try again shortly.',
      'history': 'Processing history',
      'clear': 'Clear history',
      'empty': 'No files processed yet',
      'emptyHint':
          'Selected logs upload automatically; download results when ready',
      'download': 'Download logs',
      'cancel': 'Cancel job',
      'privacy':
          'Logs are uploaded for decoding  ·  Private keys stay on the server  ·  Originals preserved',
      'limits': 'Upload limit per file',
      'fileTooLarge': 'This file exceeds the service upload limit.',
      'historyFull':
          'History is full. Wait for active jobs, then clear the history.',
      'status_uploading': 'Uploading',
      'status_queued': 'Queued',
      'status_running': 'Processing',
      'status_success': 'Completed',
      'status_warning': 'Partially recovered',
      'status_failure': 'Failed',
      'status_cancelled': 'Cancelled',
      'blocks': 'log blocks',
      'notes': 'recovery notes',
      'error_network':
          'The decoder is unavailable. Check your network or try again shortly.',
      'error_forbidden': 'This operation is not allowed.',
      'error_queue_full': 'The service is busy. Try again shortly.',
      'error_upload_too_large': 'The upload exceeds the service limit.',
      'error_invalid_input': 'No log content recovered. Check the log format.',
      'error_decode_failed': 'Could not process the log. Check the log file.',
      'error_resource_limit': 'The job exceeds the service resource limit.',
      'error_not_found':
          'This job expired or no longer exists. Upload it again.',
      'error_not_cancellable':
          'This job is already processing and cannot be cancelled yet.',
      'error_unsupported_file': 'This file format is not supported.',
      'error_unknown': 'The operation failed. Please try again.',
    },
  };
}
