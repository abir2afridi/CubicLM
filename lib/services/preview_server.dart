import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
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
  Future<String?> start(String projectId, String projectDir) async {
    try {
      if (_server != null) {
        if (_servingProjectId == projectId) return url;
        await stop();
      }
      final handler = const Pipeline()
          .addMiddleware(logRequests(logger: (_, __) {}))
          .addHandler(createStaticHandler(
            projectDir,
            defaultDocument: 'index.html',
            listDirectories: false,
          ));
      _server = await shelf_io.serve(
        handler,
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

  Future<void> stop() async {
    _servingProjectId = null;
    final s = _server;
    _server = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
  }
}
