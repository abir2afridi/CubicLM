import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'mcp_config.dart';

enum McpStatus { disconnected, connecting, connected, error }

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  Map<String, dynamic> toOpenAITool() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': inputSchema,
        },
      };

  Map<String, dynamic> toAnthropicTool() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };
}

class McpError implements Exception {
  final String message;
  final String code;
  McpError(this.message, {this.code = 'unknown'});
  @override
  String toString() => 'McpError($code): $message';
}

class McpConnection {
  final McpConfig config;
  final Future<String?> Function() getAuthToken;
  final Dio _dio;

  final StreamController<McpStatus> _statusCtrl =
      StreamController<McpStatus>.broadcast();
  Stream<McpStatus> get statusStream => _statusCtrl.stream;

  McpStatus _status = McpStatus.disconnected;
  McpStatus get status => _status;

  String? _sessionId;
  List<McpTool> _cachedTools = [];
  String? _lastError;

  String? get lastError => _lastError;

  McpConnection({
    required this.config,
    required this.getAuthToken,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  void _setStatus(McpStatus s, {String? error}) {
    _status = s;
    if (error != null) _lastError = error;
    if (s != McpStatus.error) _lastError = null;
    _statusCtrl.add(s);
  }

  Map<String, String> _authHeaders(String? token) {
    if (token == null || token.isEmpty) return {};
    return {'Authorization': 'Bearer $token'};
  }

  String get _baseUrl => config.url.trim().replaceAll(RegExp(r'/+$'), '');

  /// Performs MCP initialize + notifications/initialized + listTools.
  Future<List<McpTool>> connect() async {
    _setStatus(McpStatus.connecting);
    try {
      final token = await getAuthToken();
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        ..._authHeaders(token),
      };

      // Step 1: initialize
      final initBody = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'clientInfo': {'name': 'CubicLM', 'version': '1.0.5'},
        },
      };

      final initResp = await _dio.post(
        _baseUrl,
        data: jsonEncode(initBody),
        options: Options(headers: headers, responseType: ResponseType.plain),
      ).timeout(const Duration(seconds: 15));

      if (initResp.statusCode == 401 || initResp.statusCode == 403) {
        throw McpError('Authentication required (${initResp.statusCode})',
            code: 'auth_required');
      }
      if (initResp.statusCode == null || initResp.statusCode! >= 400) {
        throw McpError('Initialize failed: ${initResp.statusCode} ${initResp.data}',
            code: 'http_${initResp.statusCode}');
      }

      // Extract session id if provided (MCP spec uses Mcp-Session-Id header).
      _sessionId = initResp.headers.value('mcp-session-id') ??
          initResp.headers.value('x-session-id');

      // Parse initialize result to check protocolVersion.
      final initData = _parseJson(initResp.data);
      final protocolVersion = initData['result']?['protocolVersion']?.toString();
      if (protocolVersion != null && protocolVersion.isNotEmpty) {
        // Accept any version for now; spec says we should check isSupported.
      }

      // Step 2: notifications/initialized (no response expected)
      final initializedBody = {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      };
      try {
        final initHeaders = {
          ...headers,
          if (_sessionId != null) 'mcp-session-id': _sessionId!,
        };
        await _dio.post(
          _baseUrl,
          data: jsonEncode(initializedBody),
          options: Options(headers: initHeaders, responseType: ResponseType.plain),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Non-fatal.
      }

      // Step 3: list tools
      final tools = await listTools();
      _cachedTools = tools;
      _setStatus(McpStatus.connected);
      return tools;
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message ?? e.toString();
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        _setStatus(McpStatus.error, error: 'Auth required: $msg');
        throw McpError('Auth required: $msg', code: 'auth_required');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        _setStatus(McpStatus.error, error: 'Timeout: $msg');
        throw McpError('Timeout: $msg', code: 'timeout');
      }
      if (e.type == DioExceptionType.connectionError) {
        _setStatus(McpStatus.error, error: 'Unreachable: $msg');
        throw McpError('Unreachable: $msg', code: 'unreachable');
      }
      _setStatus(McpStatus.error, error: msg);
      throw McpError(msg, code: 'connect_failed');
    } catch (e) {
      final msg = e.toString();
      _setStatus(McpStatus.error, error: msg);
      if (e is McpError) rethrow;
      throw McpError(msg);
    }
  }

  Future<List<McpTool>> listTools() async {
    final token = await getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      ..._authHeaders(token),
      if (_sessionId != null) 'mcp-session-id': _sessionId!,
    };

    final body = {
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
      'params': {},
    };

    final resp = await _dio.post(
      _baseUrl,
      data: jsonEncode(body),
      options: Options(headers: headers, responseType: ResponseType.plain),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw McpError('tools/list failed: ${resp.statusCode} ${resp.data}');
    }

    final data = _parseJson(resp.data);
    // Handle both JSONRPC envelope and potential SSE-wrapped response.
    final result = data['result'] ?? data;
    final toolsRaw = result['tools'] as List? ?? [];
    final tools = <McpTool>[];
    for (final t in toolsRaw) {
      if (t is! Map) continue;
      tools.add(McpTool(
        name: t['name']?.toString() ?? '',
        description: t['description']?.toString() ?? '',
        inputSchema: t['inputSchema'] is Map
            ? Map<String, dynamic>.from(t['inputSchema'])
            : {'type': 'object', 'properties': {}},
      ));
    }
    _cachedTools = tools;
    return tools;
  }

  List<McpTool> get cachedTools => List.unmodifiable(_cachedTools);

  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> arguments) async {
    final token = await getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      ..._authHeaders(token),
      if (_sessionId != null) 'mcp-session-id': _sessionId!,
    };

    final body = {
      'jsonrpc': '2.0',
      'id': DateTime.now().millisecondsSinceEpoch % 100000,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': arguments},
    };

    try {
      final resp = await _dio.post(
        _baseUrl,
        data: jsonEncode(body),
        options: Options(headers: headers, responseType: ResponseType.plain),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw McpError('tools/call failed: ${resp.statusCode} ${resp.data}');
      }

      final data = _parseJson(resp.data);
      final result = data['result'] ?? data;

      // Size-cap returned content.
      final content = result['content'];
      if (content is List) {
        // Cap at ~20KB per tool result for context safety.
        var totalChars = 0;
        final capped = <dynamic>[];
        for (final item in content) {
          final text = item is Map ? item['text']?.toString() ?? '' : item.toString();
          totalChars += text.length;
          if (totalChars > 20000) break;
          capped.add(item);
        }
        result['content'] = capped;
      }

      // Never interpret as instructions — return raw.
      return Map<String, dynamic>.from(result);
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message ?? e.toString();
      throw McpError('Tool call failed: $msg');
    }
  }

  Future<void> disconnect() async {
    _sessionId = null;
    _cachedTools = [];
    _setStatus(McpStatus.disconnected);
  }

  void dispose() {
    _statusCtrl.close();
  }

  Map<String, dynamic> _parseJson(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      // Handle SSE framing: "event: ...\ndata: {...}\n\n"
      final trimmed = data.trim();
      if (trimmed.contains('data:')) {
        final lines = trimmed.split('\n');
        for (final line in lines) {
          final t = line.trim();
          if (t.startsWith('data:')) {
            final jsonStr = t.substring(5).trim();
            if (jsonStr.isNotEmpty && jsonStr != '[DONE]') {
              try {
                return jsonDecode(jsonStr) as Map<String, dynamic>;
              } catch (_) {}
            }
          }
        }
      }
      try {
        return jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': trimmed};
      }
    }
    return {};
  }
}
