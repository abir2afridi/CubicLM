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

  /// Hidden chats are a stronger hide than archive: excluded from the
  /// drawer AND from search hits until "Show hidden". Survives
  /// backup/restore. Old rows without the key default to false.
  final bool hidden;

  /// Free-form label/folder (e.g. "work", "study"). Empty = unlabeled.
  /// Old rows without the key default to '' (safe migration).
  final String label;

  /// Per-chat lock: opening requires device auth. Title stays visible in
  /// the drawer; only the content is gated. Old rows default to false.
  final bool locked;

  /// Pinned model override for this chat. Empty [modelMode] = follow the
  /// global inference mode. Otherwise 'local' ([modelId] = filename) or
  /// 'cloud' ([modelId] = model id, [modelProvider] = provider id,
  /// 'custom-profile:<index>' encoded in modelId when provider is custom).
  /// Old rows without the keys default to '' (safe migration).
  final String modelMode;
  final String modelId;
  final String modelProvider;

  ChatSession({
    required this.id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastMessage,
    this.pinned = false,
    this.persona = '',
    this.archived = false,
    this.hidden = false,
    this.label = '',
    this.locked = false,
    this.modelMode = '',
    this.modelId = '',
    this.modelProvider = '',
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
        'hidden': hidden,
        'label': label,
        'locked': locked,
        'modelMode': modelMode,
        'modelId': modelId,
        'modelProvider': modelProvider,
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
        hidden: map['hidden'] == true,
        label: map['label']?.toString() ?? '',
        locked: map['locked'] == true,
        modelMode: map['modelMode']?.toString() ?? '',
        modelId: map['modelId']?.toString() ?? '',
        modelProvider: map['modelProvider']?.toString() ?? '',
      );

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessage,
    bool? pinned,
    String? persona,
    bool? archived,
    bool? hidden,
    String? label,
    bool? locked,
    String? modelMode,
    String? modelId,
    String? modelProvider,
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
        hidden: hidden ?? this.hidden,
        label: label ?? this.label,
        locked: locked ?? this.locked,
        modelMode: modelMode ?? this.modelMode,
        modelId: modelId ?? this.modelId,
        modelProvider: modelProvider ?? this.modelProvider,
      );
}
