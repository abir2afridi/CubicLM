import 'dart:convert';
import 'dart:typed_data';

class ChatMessage {
  final String id;
  final String chatId;
  final String role; // 'user', 'assistant', 'system', 'cmd'
  final String content;
  final String? imageBase64; // For multimodal
  final String? imagePath;
  final String? fileName;
  final String? fileContent;
  final String? filePath;
  final String? fileType;
  final int? fileSize;
  final String? cmdOutput; // Result of CMD: execution
  final bool isCommand;
  final double? tokensPerSec;
  final int? thoughtDurationSeconds;
  final int? imageGenDurationMs; // Time taken to generate image locally
  final DateTime timestamp;

  // Cache decoded bytes to prevent flickering on re-build
  Uint8List? _decodedImageBytes;
  Uint8List? get decodedImageBytes {
    if (imageBase64 == null) return null;
    _decodedImageBytes ??= base64Decode(imageBase64!);
    return _decodedImageBytes;
  }

  ChatMessage({

    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.imageBase64,
    this.imagePath,
    this.fileName,
    this.fileContent,
    this.filePath,
    this.fileType,
    this.fileSize,
    this.cmdOutput,
    this.isCommand = false,
    this.tokensPerSec,
    this.thoughtDurationSeconds,
    this.imageGenDurationMs,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'role': role,
        'content': content,
        'imageBase64': imageBase64,
        'imagePath': imagePath,
        'fileName': fileName,
        'fileContent': fileContent,
        'filePath': filePath,
        'fileType': fileType,
        'fileSize': fileSize,
        'cmdOutput': cmdOutput,
        'isCommand': isCommand,
        'tokensPerSec': tokensPerSec,
        'thoughtDurationSeconds': thoughtDurationSeconds,
        'imageGenDurationMs': imageGenDurationMs,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromMap(Map<dynamic, dynamic> map) => ChatMessage(
        id: map['id'] ?? '',
        chatId: map['chatId'] ?? '',
        role: map['role'] ?? 'user',
        content: map['content'] ?? '',
        imageBase64: map['imageBase64'],
        imagePath: map['imagePath'],
        fileName: map['fileName'],
        fileContent: map['fileContent'],
        filePath: map['filePath'],
        fileType: map['fileType'],
        fileSize:
            map['fileSize'] != null ? (map['fileSize'] as num).toInt() : null,
        cmdOutput: map['cmdOutput'],
        isCommand: map['isCommand'] ?? false,
        tokensPerSec: map['tokensPerSec'] != null
            ? (map['tokensPerSec'] as num).toDouble()
            : null,
        thoughtDurationSeconds: map['thoughtDurationSeconds'] != null
            ? (map['thoughtDurationSeconds'] as num).toInt()
            : null,
        imageGenDurationMs: map['imageGenDurationMs'] != null
            ? (map['imageGenDurationMs'] as num).toInt()
            : null,
        timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      );
}
