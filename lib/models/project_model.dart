class ChatProject {
  final String id;
  final String name;
  final String instructions;
  final List<String> filePaths;
  final List<String> chatIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatProject({
    required this.id,
    required this.name,
    this.instructions = '',
    this.filePaths = const [],
    this.chatIds = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'instructions': instructions,
        'filePaths': filePaths,
        'chatIds': chatIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatProject.fromMap(Map<dynamic, dynamic> map) => ChatProject(
        id: map['id'] ?? '',
        name: map['name'] ?? 'Untitled Project',
        instructions: map['instructions'] ?? '',
        filePaths: List<String>.from(map['filePaths'] ?? []),
        chatIds: List<String>.from(map['chatIds'] ?? []),
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
      );

  ChatProject copyWith({
    String? name,
    String? instructions,
    List<String>? filePaths,
    List<String>? chatIds,
    DateTime? updatedAt,
  }) =>
      ChatProject(
        id: id,
        name: name ?? this.name,
        instructions: instructions ?? this.instructions,
        filePaths: filePaths ?? this.filePaths,
        chatIds: chatIds ?? this.chatIds,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}
