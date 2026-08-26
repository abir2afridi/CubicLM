class SkillModel {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final String content;
  final bool enabled;
  final bool isBuiltIn;
  final String source; // built-in | file | github | url
  final DateTime createdAt;

  SkillModel({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.content,
    this.enabled = false,
    this.isBuiltIn = false,
    this.source = 'file',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SkillModel copyWith({
    String? name,
    String? description,
    String? author,
    String? version,
    String? content,
    bool? enabled,
    bool? isBuiltIn,
    String? source,
  }) =>
      SkillModel(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        author: author ?? this.author,
        version: version ?? this.version,
        content: content ?? this.content,
        enabled: enabled ?? this.enabled,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
        source: source ?? this.source,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'author': author,
        'version': version,
        'content': content,
        'enabled': enabled,
        'isBuiltIn': isBuiltIn,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SkillModel.fromMap(Map<dynamic, dynamic> map) => SkillModel(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        description: map['description'] ?? '',
        author: map['author'] ?? '',
        version: map['version'] ?? '1.0.0',
        content: map['content'] ?? '',
        enabled: map['enabled'] ?? false,
        isBuiltIn: map['isBuiltIn'] ?? false,
        source: map['source'] ?? 'file',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      );
}
