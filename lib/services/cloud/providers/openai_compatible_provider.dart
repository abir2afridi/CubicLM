import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../cloud_provider.dart';
import '../../hive_service.dart';
import '../../mcp/mcp_registry_service.dart';

/// Abstract base class for providers that use OpenAI-compatible API format.
///
/// This includes OpenAI, DeepSeek, NVIDIA, OpenRouter, Z.AI, Kimi, and Custom.
/// Override specific methods for providers that need custom behavior.
/// Concrete subclasses must implement: id, name, description, icon, endpoint.
abstract class OpenAICompatibleProvider extends CloudProvider {
  @override
  ProviderProtocol get protocol => ProviderProtocol.openAICompatible;

  @override
  bool get supportsStreaming => true;

  List<Map<String, dynamic>>? _mcpToolsPayload() {
    try {
      if (!Get.isRegistered<McpRegistryService>()) return null;
      final reg = Get.find<McpRegistryService>();
      final cfg = reg.config.value;
      if (cfg == null || !cfg.enabled) return null;
      final tools = reg.tools;
      if (tools.isEmpty) {
        // Still expose schema if server is enabled but not yet connected — spec 3.6.
        // Try to keep cached tools even when disconnected; if none, return null
        // and let the model proceed without tools rather than blocking.
        return null;
      }
      return tools.map((t) => t.toOpenAITool()).toList();
    } catch (_) {
      return null;
    }
  }

  static const _kMcpApprovalKey = 'mcp_require_approval';
  static const _kMcpAlwaysAllowKey = 'mcp_always_allow_tools';

  /// Approval gate for MCP tool calls. Returns true when the call may run.
  /// - Tools on the always-allow list run silently.
  /// - When the approval toggle is off, everything runs (old behavior).
  /// - Otherwise a blocking dialog asks: Deny / Allow once / Always allow.
  /// Never throws — on any UI failure the call is denied (fail-closed).
  Future<bool> _approveToolCall(String name, Map<String, dynamic> args) async {
    try {
      final hive = Get.find<HiveService>();
      final always =
          (hive.getSetting<List>(_kMcpAlwaysAllowKey) ?? const [])
              .map((e) => e.toString())
              .toSet();
      if (always.contains(name)) return true;
      final require =
          hive.getSetting<bool>(_kMcpApprovalKey, defaultValue: true) ?? true;
      if (!require) return true;
      final argsText = _truncateArgs(args);
      final decision = await Get.dialog<String>(
        AlertDialog(
          title: const Text('Allow tool call?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(argsText,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Get.back(result: 'deny'),
                child: const Text('Deny')),
            TextButton(
                onPressed: () => Get.back(result: 'always'),
                child: const Text('Always allow')),
            FilledButton(
                onPressed: () => Get.back(result: 'once'),
                child: const Text('Allow once')),
          ],
        ),
        barrierDismissible: false,
      );
      if (decision == 'always') {
        try {
          await hive.setSetting(
              _kMcpAlwaysAllowKey, [...always, name].toList());
        } catch (_) {}
        return true;
      }
      return decision == 'once';
    } catch (_) {
      return false;
    }
  }

  String _truncateArgs(Map<String, dynamic> args) {
    try {
      final s = const JsonEncoder.withIndent('  ').convert(args);
      return s.length > 800 ? '${s.substring(0, 800)}…(truncated)' : s;
    } catch (_) {
      final s = args.toString();
      return s.length > 800 ? '${s.substring(0, 800)}…(truncated)' : s;
    }
  }

  Future<String> _handleToolCalls(
    List<Map<String, String>> messages,
    String apiKey,
    String model,
    Map<String, dynamic> firstMessage,
    List<dynamic> toolCalls,
  ) async {
    if (!Get.isRegistered<McpRegistryService>()) {
      return firstMessage['content']?.toString() ?? '';
    }
    final reg = Get.find<McpRegistryService>();
    final toolResults = <Map<String, dynamic>>[];
    for (final tc in toolCalls) {
      if (tc is! Map) continue;
      final id = tc['id']?.toString() ?? 'call_${DateTime.now().microsecondsSinceEpoch}';
      final fn = tc['function'] is Map ? tc['function'] as Map : {};
      final name = fn['name']?.toString() ?? '';
      final argsRaw = fn['arguments']?.toString() ?? '{}';
      Map<String, dynamic> args;
      try {
        args = jsonDecode(argsRaw) is Map
            ? Map<String, dynamic>.from(jsonDecode(argsRaw))
            : {};
      } catch (_) {
        args = {};
      }
      Map<String, dynamic> result;
      try {
        final allowed = await _approveToolCall(name, args);
        if (!allowed) {
          result = {
            'content': [
              {'type': 'text', 'text': 'Tool $name was denied by the user.'}
            ],
            'isError': true,
          };
        } else {
          result = await reg.callTool(name, args);
        }
      } catch (e) {
        result = {
          'content': [
            {'type': 'text', 'text': 'Tool $name failed: $e'}
          ],
          'isError': true,
        };
      }
      // Cap result text for context safety.
      String resultText;
      try {
        final content = result['content'];
        if (content is List) {
          resultText = content
              .map((c) => c is Map ? c['text']?.toString() ?? jsonEncode(c) : c.toString())
              .join('\n');
        } else {
          resultText = jsonEncode(result);
        }
        if (resultText.length > 18000) {
          resultText = '${resultText.substring(0, 18000)}\n…(truncated)';
        }
      } catch (_) {
        resultText = result.toString();
      }
      toolResults.add({
        'role': 'tool',
        'tool_call_id': id,
        'content': resultText,
      });
    }

    // Second request with tool results appended.
    final mcpTools = _mcpToolsPayload();
    final extendedMessages = [
      ...messages,
      {
        'role': 'assistant',
        'content': firstMessage['content']?.toString() ?? '',
        'tool_calls': toolCalls,
      },
      ...toolResults.map((r) => {'role': r['role'] as String, 'tool_call_id': r['tool_call_id'] as String, 'content': r['content'] as String}),
    ];

    // Preserve original tool_calls structure in second request by re-injecting raw.
    // For OpenAI, we need the assistant message with tool_calls as is.
    // Rebuild apiMessages manually to keep tool_calls.
    final apiMessages2 = <Map<String, dynamic>>[];
    for (final m in extendedMessages) {
      if (m.containsKey('tool_calls')) {
        apiMessages2.add({
          'role': 'assistant',
          'content': m['content'],
          'tool_calls': m['tool_calls'],
        });
      } else {
        apiMessages2.add({'role': m['role'], 'content': m['content']});
      }
    }
    final body2Fixed = {
      'model': model,
      if (mcpTools != null) 'tools': mcpTools,
      if (mcpTools != null) 'tool_choice': 'auto',
      'messages': apiMessages2,
    };

    final resp2 = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            ...buildAuthHeaders(apiKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body2Fixed),
        )
        .timeout(const Duration(minutes: 3));

    if (resp2.statusCode != 200) {
      throw Exception(
          '${runtimeType.toString()} tool follow-up error: ${resp2.statusCode} ${resp2.body}');
    }
    final data2 = jsonDecode(resp2.body);
    return data2['choices'][0]['message']['content']?.toString() ?? '';
  }

  @override
  Future<String> sendMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async {
    final mcpTools = _mcpToolsPayload();
    final body = buildRequestBody(
      messages: messages,
      model: model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: false,
      mcpTools: mcpTools,
    );

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            ...buildAuthHeaders(apiKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode != 200) {
      throw Exception(
          '${runtimeType.toString()} API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final message = data['choices'][0]['message'] as Map<String, dynamic>? ?? {};
    final toolCalls = message['tool_calls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty && mcpTools != null) {
      return _handleToolCalls(messages, apiKey, model, message, toolCalls);
    }
    return message['content']?.toString() ?? '';
  }

  @override
  Stream<String> streamMessage({
    required List<Map<String, String>> messages,
    required String apiKey,
    required String model,
    String? imageBase64,
    double? temperature,
    int? maxTokens,
  }) async* {
    final mcpTools = _mcpToolsPayload();
    final body = buildRequestBody(
      messages: messages,
      model: model,
      imageBase64: imageBase64,
      temperature: temperature,
      maxTokens: maxTokens,
      stream: true,
      mcpTools: mcpTools,
    );

    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers.addAll({
      ...buildAuthHeaders(apiKey),
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode(body);

    final streamedResponse = await request.send().timeout(
          const Duration(minutes: 3),
        );

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw Exception(
          '${runtimeType.toString()} streaming error: ${streamedResponse.statusCode} $errorBody');
    }

    // If MCP tools are active, we need to detect tool_calls in the stream.
    final List<Map<String, dynamic>> pendingToolCalls = [];

    String buffer = '';
    await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
        final jsonStr = trimmed.substring(6);
        if (jsonStr == '[DONE]') {
          // Tool handling will happen after loop if needed.
          if (pendingToolCalls.isNotEmpty) {
            final finalAnswer = await _handleToolCalls(
                messages, apiKey, model, {'content': ''}, pendingToolCalls);
            // Yield final answer chunked.
            for (final word in finalAnswer.split(' ')) {
              if (word.isNotEmpty) yield '$word ';
            }
          }
          return;
        }

        try {
          final data = jsonDecode(jsonStr);
          final choice = data['choices']?[0];
          final delta = choice?['delta'];
          if (delta == null) continue;
          final content = delta['content'];
          if (content != null) yield content.toString();

          // Tool calls in streaming delta.
          final toolCallsDelta = delta['tool_calls'] as List?;
          if (toolCallsDelta != null && mcpTools != null) {
            for (final tc in toolCallsDelta) {
              if (tc is! Map) continue;
              final idx = (tc['index'] as num?)?.toInt() ?? 0;
              while (pendingToolCalls.length <= idx) {
                pendingToolCalls.add({
                  'id': '',
                  'type': 'function',
                  'function': {'name': '', 'arguments': ''}
                });
              }
              final existing = pendingToolCalls[idx];
              if (tc['id'] != null) existing['id'] = tc['id'].toString();
              if (tc['type'] != null) existing['type'] = tc['type'].toString();
              final fn = tc['function'];
              if (fn is Map) {
                final existingFn = existing['function'] as Map<String, dynamic>;
                if (fn['name'] != null) {
                  existingFn['name'] = fn['name'].toString();
                }
                if (fn['arguments'] != null) {
                  existingFn['arguments'] =
                      (existingFn['arguments']?.toString() ?? '') +
                          fn['arguments'].toString();
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    if (buffer.trim().isNotEmpty) {
      final trimmed = buffer.trim();
      if (trimmed.startsWith('data: ') && trimmed.substring(6) != '[DONE]') {
        try {
          final data = jsonDecode(trimmed.substring(6));
          final delta = data['choices']?[0]?['delta']?['content'];
          if (delta != null) yield delta.toString();
        } catch (_) {}
      }
    }

    if (pendingToolCalls.isNotEmpty) {
      final finalAnswer = await _handleToolCalls(
          messages, apiKey, model, {'content': ''}, pendingToolCalls);
      for (final word in finalAnswer.split(' ')) {
        if (word.isNotEmpty) yield '$word ';
      }
    }
  }

  @override
  List<String> parseModelIds(String body) {
    final data = jsonDecode(body);
    List<String> tryExtract(Map root) {
      for (final key in ['data', 'models', 'results', 'items', 'model_list']) {
        final raw = root[key];
        if (raw is List && raw.isNotEmpty) {
          final ids = raw
              .map((m) {
                if (m is! Map) return null;
                return m['id']?.toString() ??
                    m['name']?.toString() ??
                    m['model']?.toString();
              })
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          if (ids.isNotEmpty) return ids;
        }
      }
      return const [];
    }

    if (data is Map<String, dynamic>) {
      final ids = tryExtract(data);
      if (ids.isNotEmpty) return ids;
    }

    if (data is List) {
      final ids = data
          .map((m) {
            if (m is! Map) return null;
            return m['id']?.toString() ??
                m['name']?.toString() ??
                m['model']?.toString();
          })
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) return ids;
    }

    return const [];
  }
}
