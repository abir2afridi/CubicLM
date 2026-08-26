enum McpTransport { http, sse }

enum McpAuthType { none, bearer }

class McpConfig {
  final String name;
  final String url;
  final McpTransport transport;
  final McpAuthType authType;
  final bool enabled;

  McpConfig({
    required this.name,
    required this.url,
    this.transport = McpTransport.http,
    this.authType = McpAuthType.none,
    this.enabled = false,
  });

  McpConfig copyWith({
    String? name,
    String? url,
    McpTransport? transport,
    McpAuthType? authType,
    bool? enabled,
  }) =>
      McpConfig(
        name: name ?? this.name,
        url: url ?? this.url,
        transport: transport ?? this.transport,
        authType: authType ?? this.authType,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'transport': transport.name,
        'authType': authType.name,
        'enabled': enabled,
      };

  factory McpConfig.fromMap(Map<dynamic, dynamic> m) => McpConfig(
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
