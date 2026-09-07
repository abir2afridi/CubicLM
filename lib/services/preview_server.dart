import 'dart:async';
import 'dart:io';

import 'package:get/get.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

/// Localhost static server for agent-IDE project previews.
///
/// - Serves one project dir on 127.0.0.1 (random port) so relative
///   assets resolve and localStorage gets a real origin.
/// - Injects a console-error reporter page wrapper? No — the WebView's
///   onConsoleMessage already surfaces JS errors; the server stays dumb.
/// - Stopped explicitly; only one project served at a time (MVP).
class PreviewServerService extends GetxService {
  HttpServer? _server;
  String? _servingProjectId;

  bool get isRunning => _server != null;
  String? get servingProjectId => _servingProjectId;

  int get port => _server?.port ?? 0;

  String? get url =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}/';

  /// Serve [projectDir]; restarts if another project is up.
  /// Returns the base URL, or null on failure (never throws).
  /// Unknown paths get a friendly page (not a bare 404) explaining that
  /// framework builds needing Node can't preview statically.
  Future<String?> start(String projectId, String projectDir) async {
    try {
      if (_server != null) {
        if (_servingProjectId == projectId) return url;
        await stop();
      }
      final staticHandler = createStaticHandler(
        projectDir,
        defaultDocument: 'index.html',
        listDirectories: false,
      );
      Future<Response> handler(Request request) async {
        final res = await staticHandler(request);
        if (res.statusCode == 404) return _notFoundPage(request);
        return res;
      }

      final wrapped = const Pipeline()
          .addMiddleware(logRequests(logger: (_, __) {}))
          .addHandler(handler);
      _server = await shelf_io.serve(
        wrapped,
        InternetAddress.loopbackIPv4,
        0,
      );
      _servingProjectId = projectId;
      return url;
    } catch (_) {
      try {
        await stop();
      } catch (_) {}
      return null;
    }
  }

  Response _notFoundPage(Request request) {
    // Neutral 404 for missing ASSET paths only. Framework-vs-static
    // routing (and its specific error states) lives in the preview
    // router + diagnosis card — never in this fallback page.
    const html = '''<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>File not found</title>
<style>body{font-family:system-ui;background:#14141c;color:#f2f0ea;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center}h1{font-size:20px;margin-bottom:10px}p{color:#9a958c;font-size:14px;line-height:1.6}a{color:#d97757}</style>
</head><body><div><h1>File not found in this project</h1>
<p>The requested path does not exist in the project files. Check the Files tab for the exact path, or see the diagnosis card above the preview for runtime status.</p></div></body></html>''';
    return Response.notFound(html,
        headers: {'content-type': 'text/html; charset=utf-8'});
  }

  Future<void> stop() async {
    _servingProjectId = null;
    final s = _server;
    _server = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
  }
}
