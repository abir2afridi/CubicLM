import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cubiclm/services/app_log_service.dart';

class _FakePaths extends PathProviderPlatform {
  final Directory dir;
  _FakePaths(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() =>
      Future.value(dir.path);
}

/// Kill-proof breadcrumb: a SIGKILL between setBreadcrumb and the next
/// boot must leave evidence, and takeBreadcrumb must consume it once.
void main() {
  late Directory tmp;

  setUpAll(() {
    Get.testMode = true;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crumb_test_');
    PathProviderPlatform.instance = _FakePaths(tmp);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('breadcrumb round-trips and is consumed once', () async {
    final logs = AppLogService();
    expect(await logs.takeBreadcrumb(), isNull);

    await logs.setBreadcrumb('native-load-start', 'tiny.gguf (1MB)');
    final got = await logs.takeBreadcrumb();
    expect(got, isNotNull);
    expect(got!['step'], 'native-load-start');
    expect(got['detail'], 'tiny.gguf (1MB)');
    expect(got['at'], isNotEmpty);

    // Consumed: second take finds nothing (clean shutdown look).
    expect(await logs.takeBreadcrumb(), isNull);
  });

  test('done breadcrumb resolves a start (no false death report)', () async {
    final logs = AppLogService();
    await logs.setBreadcrumb('native-load-start', 'm.gguf');
    await logs.setBreadcrumb('model-load-done', 'm.gguf');
    final got = await logs.takeBreadcrumb();
    expect(got!['step'], 'model-load-done');
    expect(await logs.takeBreadcrumb(), isNull);
  });
}
