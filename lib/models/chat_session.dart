class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final bool pinned;

  /// Per-chat persona (system-prompt addition). Empty = use global only.
  /// Old rows without the key default to '' (safe migration).
  final String persona;

  /// Archived chats hide from the drawer (toggle to reveal). Survives
  /// backup/restore and never auto-deletes.
  final bool archived;

  ChatSession({
    required this.id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastMessage,
    this.pinned = false,
    this.persona = '',
    this.archived = false,
  })  : title = title ?? 'New Chat',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastMessage': lastMessage,
        'pinned': pinned,
        'persona': persona,
        'archived': archived,
      };

  factory ChatSession.fromMap(Map<dynamic, dynamic> map) => ChatSession(
        id: map['id'] ?? '',
        title: map['title'] ?? 'New Chat',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
        lastMessage: map['lastMessage'],
        pinned: map['pinned'] == true,
        persona: map['persona']?.toString() ?? '',
        archived: map['archived'] == true,
      );

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessage,
    bool? pinned,
    String? persona,
    bool? archived,
  }) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        lastMessage: lastMessage ?? this.lastMessage,
        pinned: pinned ?? this.pinned,
        persona: persona ?? this.persona,
        archived: archived ?? this.archived,
      );
}
