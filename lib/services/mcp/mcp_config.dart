enum McpTransport { http, sse }

enum McpAuthType { none, bearer }

class McpConfig {
  /// Stable id (uuid). Legacy single-server rows default to '' and are
  /// assigned one on migration.
  final String id;
  final String name;
  final String url;
  final McpTransport transport;
  final McpAuthType authType;
  final bool enabled;

  McpConfig({
    String? id,
    required this.name,
    required this.url,
    this.transport = McpTransport.http,
    this.authType = McpAuthType.none,
    this.enabled = false,
  }) : id = (id == null || id.isEmpty)
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : id;

  McpConfig copyWith({
    String? id,
    String? name,
    String? url,
    McpTransport? transport,
    McpAuthType? authType,
    bool? enabled,
  }) =>
      McpConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        url: url ?? this.url,
        transport: transport ?? this.transport,
        authType: authType ?? this.authType,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'transport': transport.name,
        'authType': authType.name,
        'enabled': enabled,
      };

  factory McpConfig.fromMap(Map<dynamic, dynamic> m) => McpConfig(
        id: m['id']?.toString() ?? '',
        name: m['name'] ?? '',
        url: m['url'] ?? '',
        transport: McpTransport.values.firstWhere(
            (e) => e.name == m['transport'],
            orElse: () => McpTransport.http),
        authType: McpAuthType.values.firstWhere(
            (e) => e.name == m['authType'],
            orElse: () => McpAuthType.none),
        enabled: m['enabled'] ?? false,
      );

  bool get isValid => url.trim().isNotEmpty && Uri.tryParse(url.trim()) != null;

  static McpTransport inferTransport(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/sse') || lower.contains('sse')) return McpTransport.sse;
    return McpTransport.http;
  }
}
