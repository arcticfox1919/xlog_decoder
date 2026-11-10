@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:jaspr_test/client_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web/web.dart' as web;
import 'package:xlog_web/app.dart';
import 'package:xlog_web/browser/browser_environment.dart';
import 'package:xlog_web/browser/browser_upload_file.dart';
import 'package:xlog_web/features/decoder/application/decoder_controller.dart';
import 'package:xlog_web/features/decoder/data/backend_api.dart';
import 'package:xlog_web/features/decoder/domain/decoder_api.dart';
import 'package:xlog_web/features/decoder/domain/models.dart';
import 'package:xlog_web/features/decoder/presentation/components/upload_panel.dart';
import 'package:xlog_web/l10n/strings.dart';

class FakeBackendApi extends BackendApi {
  FakeBackendApi(
    super.baseUri, {
    this.uploadStatus = 'success',
    this.available = true,
  });

  final String uploadStatus;
  bool available;
  int healthCalls = 0;
  final uploads = <String>[];
  final cancelledJobs = <String>[];

  @override
  Future<int> health() async {
    healthCalls++;
    if (!available) throw const ApiException('network');
    return 256 * 1024 * 1024;
  }

  @override
  Future<RemoteJob> upload(
    UploadFile file, {
    required void Function(double progress) onProgress,
  }) async {
    uploads.add(file.name);
    onProgress(1);
    return RemoteJob(
      id: 'job-test',
      name: file.name,
      status: uploadStatus,
      outputBytes: 14,
      blockCount: 1,
      downloadUrl: uploadStatus == 'success'
          ? '/api/jobs/job-test/download'
          : null,
    );
  }

  @override
  Future<RemoteJob> job(String id) async =>
      RemoteJob(id: id, name: uploads.last, status: uploadStatus);

  @override
  Future<void> cancel(String id) async => cancelledJobs.add(id);
}

Future<void> _flush() => pumpEventQueue(times: 30);

web.DataTransfer _files(String name) {
  final transfer = web.DataTransfer();
  transfer.items.add(
    web.File(
      <JSAny>[
        Uint8List.fromList([1, 2, 3]).toJS,
      ].toJS,
      name,
    ),
  );
  return transfer;
}

void main() {
  late List<FakeBackendApi> clients;

  setUp(() {
    clients = [];
    web.window.localStorage.clear();
    web.window.localStorage.setItem('xlog.language', 'zh');
  });
  tearDown(() => web.window.localStorage.clear());

  App app({String uploadStatus = 'success', bool available = true}) => App(
    createApi: (uri) {
      final api = FakeBackendApi(
        uri,
        uploadStatus: uploadStatus,
        available: clients.isEmpty ? available : clients.last.available,
      );
      clients.add(api);
      return api;
    },
  );

  testClient(
    'Automatically prepares same-origin API and switches languages without service settings',
    (tester) async {
      tester.pumpComponent(app());
      await _flush();

      expect(find.text('解密密钥由后端配置，系统自动识别日志并完成解码或解密。'), findsOneComponent);
      expect(web.document.querySelector('#server-key'), isNull);
      expect(web.document.querySelectorAll('select').length, 1);
      expect(web.document.querySelector('#private-key'), isNull);
      expect(web.document.querySelector('input[type="password"]'), isNull);
      expect(web.document.querySelector('#server-address'), isNull);
      expect(web.document.querySelector('#access-token'), isNull);
      expect(web.document.querySelector('.settings-panel'), isNull);
      expect(clients.single.baseUri, Uri.parse('${Uri.base.origin}/'));
      expect(clients.single.healthCalls, 1);
      expect(
        (web.document.querySelector('#log-files')! as web.HTMLInputElement)
            .disabled,
        isFalse,
      );
      expect(clients, hasLength(1));

      final language =
          web.document.querySelector('#language')! as web.HTMLSelectElement;
      language.value = 'en';
      language.dispatchEvent(web.Event('change'));
      await _flush();

      expect(
        find.text(const Strings('en').text('automaticDecryption')),
        findsOneComponent,
      );
      expect(find.text('Select files'), findsOneComponent);
      expect(web.document.title, 'Xlog Decoder');
      expect(web.window.localStorage.getItem('xlog.language'), 'en');
    },
  );

  testClient('Native file selection uploads directly and exposes a download', (
    tester,
  ) async {
    tester.pumpComponent(app());
    await _flush();
    final input =
        web.document.querySelector('#log-files')! as web.HTMLInputElement;
    input.files = _files('picked.xlog').files;
    input.dispatchEvent(web.Event('change'));
    await _flush();

    expect(clients.single.uploads, ['picked.xlog']);
    expect(find.text('picked.xlog'), findsOneComponent);
    expect(find.text('已完成'), findsOneComponent);
    final download =
        web.document.querySelector('a[download]')! as web.HTMLAnchorElement;
    expect(Uri.parse(download.href).path, '/api/jobs/job-test/download');
    expect(Uri.parse(download.href).hasQuery, isFalse);
    expect(download.getAttribute('referrerpolicy'), 'no-referrer');
    expect(download.textContent, '下载日志');
    expect(download.classList.contains('primary-button'), isTrue);
    expect(input.value, isEmpty);
  });

  testClient(
    'Service failure disables upload and retries without configuration',
    (tester) async {
      tester.pumpComponent(app(available: false));
      await _flush();
      expect(web.document.querySelector('[role="alert"]'), isNotNull);
      expect(
        (web.document.querySelector('#log-files')! as web.HTMLInputElement)
            .disabled,
        isTrue,
      );
      expect(web.document.querySelector('#server-key'), isNull);
      expect(web.document.querySelector('#server-address'), isNull);
      expect(web.document.querySelector('#access-token'), isNull);
      web.document
          .querySelector('.drop-zone')!
          .dispatchEvent(
            web.DragEvent(
              'drop',
              web.DragEventInit(dataTransfer: _files('unavailable.xlog')),
            ),
          );
      await _flush();
      expect(clients.single.uploads, isEmpty);
      (web.document.querySelector('.retry-service')! as web.HTMLButtonElement)
          .click();
      await _flush();
      expect(clients, hasLength(2));
      expect(web.document.querySelector('[role="alert"]'), isNotNull);
      clients.last.available = true;
      (web.document.querySelector('.retry-service')! as web.HTMLButtonElement)
          .click();
      await _flush();
      expect(clients, hasLength(3));
      expect(web.document.querySelector('[role="alert"]'), isNull);
      expect(
        (web.document.querySelector('#log-files')! as web.HTMLInputElement)
            .disabled,
        isFalse,
      );
      expect(web.window.localStorage.length, 1);
      expect(web.window.localStorage.getItem('xlog.language'), 'zh');
    },
  );

  testClient('Upload hover preserves language selection and its focus', (
    tester,
  ) async {
    tester.pumpComponent(app());
    await _flush();
    final language =
        web.document.querySelector('#language')! as web.HTMLSelectElement;
    language.value = 'en';
    language.dispatchEvent(web.Event('change'));
    await _flush();
    language.focus();
    final dropZone = web.document.querySelector('.drop-zone')!;

    dropZone.dispatchEvent(web.DragEvent('dragover'));
    await _flush();

    expect(dropZone.getAttribute('data-active'), 'true');
    expect(web.document.querySelector('#language'), same(language));
    expect(language.value, 'en');
    expect(web.document.activeElement, same(language));
    expect(clients, hasLength(1));

    dropZone.dispatchEvent(web.DragEvent('dragleave'));
    await _flush();
    expect(dropZone.getAttribute('data-active'), 'false');
    expect(web.document.activeElement, same(language));
  });

  testClient('UploadPanel drops native files and resets its hover state', (
    tester,
  ) async {
    final received = <UploadFile>[];
    tester.pumpComponent(
      UploadPanel(
        strings: const Strings('zh'),
        enabled: true,
        uploading: false,
        onFiles: received.addAll,
      ),
    );
    await _flush();
    final dropZone = web.document.querySelector('.drop-zone')!;
    dropZone.dispatchEvent(web.DragEvent('dragover'));
    await _flush();
    expect(dropZone.getAttribute('data-active'), 'true');

    dropZone.dispatchEvent(
      web.DragEvent(
        'drop',
        web.DragEventInit(dataTransfer: _files('drop.xlog')),
      ),
    );
    await _flush();

    expect(received, hasLength(1));
    expect(received.single.name, 'drop.xlog');
    expect(received.single.size, 3);
    expect(dropZone.getAttribute('data-active'), 'false');
  });

  testClient('History cancels a queued job before allowing it to be cleared', (
    tester,
  ) async {
    tester.pumpComponent(app(uploadStatus: 'queued'));
    await _flush();
    final input =
        web.document.querySelector('#log-files')! as web.HTMLInputElement;
    input.files = _files('queued.xlog').files;
    input.dispatchEvent(web.Event('change'));
    await _flush();
    final clear =
        web.document.querySelector('.history-heading button')!
            as web.HTMLButtonElement;
    expect(clear.disabled, isTrue);

    (web.document.querySelector('.job-actions button')!
            as web.HTMLButtonElement)
        .click();
    await _flush();

    expect(clients.single.cancelledJobs, ['job-test']);
    expect(find.text('已取消'), findsOneComponent);
    expect(web.document.querySelector('.job-actions button'), isNull);
    expect(clear.disabled, isFalse);
    clear.click();
    await _flush();
    expect(web.document.querySelector('.job-card'), isNull);
    expect(web.document.querySelector('.empty-state'), isNotNull);
    expect(clear.disabled, isTrue);
  });

  test(
    'Browser environment defaults to same origin without reading old service preferences',
    () {
      web.window.localStorage.setItem(
        'xlog.serverAddress',
        'https://other.example/',
      );
      web.window.localStorage.setItem('xlog.accessToken', 'old-secret');
      expect(
        BrowserEnvironment().initialServiceAddress(),
        Uri.parse('${Uri.base.origin}/'),
      );
    },
  );

  test(
    'Backend API requests use same-origin paths without authorization',
    () async {
      final requests = <http.Request>[];
      final api = BackendApi(
        Uri.parse('${Uri.base.origin}/'),
        client: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/api/health' => http.Response('{"maxUploadBytes":123}', 200),
            _ => http.Response(
              '{"id":"job","name":"app.xlog","status":"cancelled"}',
              200,
            ),
          };
        }),
      );
      addTearDown(api.close);
      final controller = DecoderController(
        baseUri: api.baseUri,
        createApi: (_) => api,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.state.ready, isTrue);
      expect(controller.state.maxUploadBytes, 123);
      expect(requests.map((request) => request.url.path), ['/api/health']);
      await api.job('job');
      await api.cancel('job');
      expect(requests.map((request) => request.url.path), [
        '/api/health',
        '/api/jobs/job',
        '/api/jobs/job',
      ]);
      for (final request in requests) {
        expect(request.url.origin, Uri.base.origin);
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
      }
      expect(
        api.downloadLink(
          const RemoteJob(
            id: 'job',
            name: 'app.xlog',
            status: 'success',
            downloadUrl: '/api/jobs/job/download',
          ),
        ),
        '${Uri.base.origin}/api/jobs/job/download',
      );
    },
  );

  test(
    'Native upload sends the original File with only its filename in the URL',
    () async {
      final request = web.XMLHttpRequest();
      String? method;
      Uri? uploadUri;
      JSAny? sentBody;
      final headers = <String, String>{};
      request.setProperty(
        'open'.toJS,
        ((JSString verb, JSString url) {
          method = verb.toDart;
          uploadUri = Uri.parse(url.toDart);
        }).toJS,
      );
      request.setProperty(
        'setRequestHeader'.toJS,
        ((JSString name, JSString value) {
          headers[name.toDart.toLowerCase()] = value.toDart;
        }).toJS,
      );
      request.setProperty(
        'send'.toJS,
        ((JSAny? body) {
          sentBody = body;
          // End this intercepted request without sending test data over HTTP.
          request.dispatchEvent(web.Event('error'));
        }).toJS,
      );
      final file = _files('app & archive.xlog').files.item(0)!;
      final api = BackendApi(
        Uri.parse('${Uri.base.origin}/'),
        createUploadRequest: () => request,
      );
      addTearDown(api.close);
      await expectLater(
        api.upload(BrowserUploadFile(file), onProgress: (_) {}),
        throwsA(
          isA<ApiException>().having((error) => error.code, 'code', 'network'),
        ),
      );
      expect(method, 'POST');
      expect(uploadUri!.origin, Uri.base.origin);
      expect(uploadUri!.path, '/api/jobs');
      expect(uploadUri!.queryParameters, {'filename': file.name});
      expect(uploadUri!.queryParameters.containsKey('keyId'), isFalse);
      expect(identical(sentBody, file), isTrue);
      expect(headers['content-type'], 'application/octet-stream');
      expect(headers.containsKey('authorization'), isFalse);
    },
  );
}
