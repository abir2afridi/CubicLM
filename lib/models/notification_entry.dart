class NotificationEntry {
  final String id;
  final String title;
  final String message;
  final String type; // model_switched | cloud_active | local_active | image_model
  final String iconName; // Lucide icon key: layers, cloud, cpu, image, sparkles
  final DateTime timestamp;
  final bool isRead;

  NotificationEntry({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.iconName,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();

  NotificationEntry copyWith({bool? isRead}) => NotificationEntry(
        id: id,
        title: title,
        message: message,
        type: type,
        iconName: iconName,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'message': message,
        'type': type,
        'iconName': iconName,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory NotificationEntry.fromMap(Map<dynamic, dynamic> map) =>
      NotificationEntry(
        id: map['id'] ?? '',
        title: map['title'] ?? '',
        message: map['message'] ?? '',
        type: map['type'] ?? 'model_switched',
        iconName: map['iconName'] ?? 'layers',
        timestamp:
            DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
        isRead: map['isRead'] ?? false,
      );
}
