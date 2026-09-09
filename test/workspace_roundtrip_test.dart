import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cubiclm/services/agent_workspace.dart';

class _FakePaths extends PathProviderPlatform {
  final Directory dir;
  _FakePaths(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() =>
      Future.value(dir.path);
}

/// Write→read round-trip through the real workspace writer (§12/§15):
/// JSX, backticks, anchors and braces must survive byte-for-byte.
void main() {
  late Directory tmp;

  setUpAll(() {
    Get.testMode = true;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ws_test_');
    PathProviderPlatform.instance = _FakePaths(tmp);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  const nasty = {
    'app/page.jsx':
        "export default function Page() {\n  const id = `g-\${a.slice(1)}`;\n  return (\n    <>\n      <Navigation />\n      <a href=\"#contact\">x</a>\n      {children}\n    </>\n  );\n}\n",
    'app/layout.jsx':
        "export default function RootLayout({ children }) {\n  return <html lang=\"en\"><body>{children}</body></html>;\n}\n",
  };

  test('writeFile + readFile round-trips source exactly', () async {
    final ws = AgentWorkspaceService();
    final p = await ws.createProject('t', 'Next.js');
    for (final e in nasty.entries) {
      expect(await ws.writeFile(p.id, e.key, e.value), isNull);
    }
    for (final e in nasty.entries) {
      expect(await ws.readFile(p.id, e.key), e.value);
    }
  });

  test('importFiles then listFiles keeps every path', () async {
    final ws = AgentWorkspaceService();
    final p = await ws.createProject('t', 'Next.js');
    expect(await ws.importFiles(p.id, nasty), isNull);
    final listed = await ws.listFiles(p.id);
    for (final k in nasty.keys) {
      expect(listed, contains(k));
    }
  });
}
