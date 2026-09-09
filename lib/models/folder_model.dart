class ChatFolder {
  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;

  ChatFolder({
    required this.id,
    required this.name,
    this.parentId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatFolder.fromMap(Map<dynamic, dynamic> map) => ChatFolder(
        id: map['id'] ?? '',
        name: map['name'] ?? 'New Folder',
        parentId: map['parentId'],
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      );
}
