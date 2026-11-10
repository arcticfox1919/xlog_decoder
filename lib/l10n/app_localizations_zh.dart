// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Xlog 解码器';

  @override
  String get appSubtitle => 'Narwal 日志解码工具';

  @override
  String get localProcessing => '本地处理';

  @override
  String get privacyNote => '全程本地处理  ·  保留原文件  ·  同名自动编号';

  @override
  String get language => '语言';

  @override
  String get systemLanguage => '跟随系统';

  @override
  String get languageSaveError => '无法保存语言设置，请重试。';

  @override
  String get languageLoadError => '无法读取语言设置，已使用系统语言。';

  @override
  String get loadSettingsError => '无法读取已保存的设置，请重新选择目录或输入私钥。';

  @override
  String get saveSettingsError => '设置保存失败，本次修改未保存，请检查本机存储权限。';

  @override
  String dialogError(String error) {
    return '无法打开文件选择窗口：$error';
  }

  @override
  String get dropFoldersError => '请拖入日志文件或 ZIP 文件，不支持直接拖入文件夹。';

  @override
  String dropReadError(String error) {
    return '无法读取拖入的文件：$error';
  }

  @override
  String get addLogs => '添加日志';

  @override
  String get multipleSelection => '支持多选';

  @override
  String get decodingLogs => '正在解码日志…';

  @override
  String get releaseToDecode => '松开，开始解码';

  @override
  String get dropLogs => '拖入日志或 ZIP';

  @override
  String get resultsBelow => '完成后可在下方查看结果';

  @override
  String get dropDescription => '自动解压、解密，生成可读日志';

  @override
  String get selectFiles => '选择文件';

  @override
  String get decoderSettings => '解码设置';

  @override
  String get autoSave => '自动保存';

  @override
  String get outputDirectory => '输出目录';

  @override
  String get chooseOutputDirectory => '点击选择输出目录';

  @override
  String get sourceDirectory => '原文件所在目录';

  @override
  String get resetDirectory => '恢复默认';

  @override
  String get privateKey => '解密私钥';

  @override
  String get optional => '可选';

  @override
  String get privateKeyHint => '64 位十六进制私钥';

  @override
  String get hidePrivateKey => '隐藏私钥';

  @override
  String get showPrivateKey => '显示私钥';

  @override
  String get importPrivateKey => '从文件导入私钥';

  @override
  String get privateKeyHelp => '未加密日志可留空。私钥加密保存在本机，清空输入即可删除。';

  @override
  String get invalidPrivateKey => '私钥需为有效的 64 位十六进制字符串；未加密日志可留空。';

  @override
  String get logFiles => '日志或 ZIP';

  @override
  String get allFiles => '所有文件';

  @override
  String get setOutputDirectory => '设为输出目录';

  @override
  String get processingHistory => '处理记录';

  @override
  String get clearHistory => '清空记录';

  @override
  String get noHistory => '还没有处理记录';

  @override
  String get outputHelp => '生成 .log 日志，ZIP 结果保存到独立文件夹';

  @override
  String get statusQueued => '等待中';

  @override
  String get statusRunning => '处理中';

  @override
  String get statusSuccess => '已完成';

  @override
  String get statusWarning => '部分恢复';

  @override
  String get statusFailure => '未完成';

  @override
  String get copyOutputPath => '复制输出路径';

  @override
  String get outputPathCopied => '已复制输出路径';

  @override
  String get inputMissing => '找不到输入文件，请重新选择。';

  @override
  String get zipEntryTooLarge => 'ZIP 内单个日志超过 256 MiB。';

  @override
  String get zipEntryUnreadable => '无法读取 ZIP 内的日志。';

  @override
  String get zipChecksumFailed => 'ZIP 文件校验失败，日志可能已损坏。';

  @override
  String get zipNoLogs => 'ZIP 内没有找到 .xlog、.log 或 .bin 日志文件。';

  @override
  String get noLogContent => '未恢复到日志内容，请检查文件格式及解密私钥。';

  @override
  String taskCount(int count) {
    return '$count 个任务';
  }

  @override
  String generatedLogs(int count) {
    return '已生成 $count 个日志';
  }

  @override
  String failedLogs(int count) {
    return '$count 个失败';
  }

  @override
  String skippedEntries(int count) {
    return '跳过 $count 个非日志条目';
  }

  @override
  String logBlocks(int count) {
    return '$count 个日志块';
  }

  @override
  String recoveryHints(int count, String details) {
    return '恢复提示（$count）\n$details';
  }

  @override
  String get languageName => '简体中文';
}
