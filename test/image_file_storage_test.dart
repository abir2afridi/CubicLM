import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cubiclm/models/chat_message.dart';

void main() {
  group('ChatMessage file-backed images', () {
    test('decodedImageBytes falls back to imagePath file', () async {
      final dir = await Directory.systemTemp.createTemp('clm_test_');
      final file = File('${dir.path}/test.png');
      final bytes = Uint8List.fromList(List.generate(100, (i) => i % 256));
      await file.writeAsBytes(bytes);

      final msg = ChatMessage(
        id: 'test-id',
        chatId: 'chat-1',
        role: 'assistant',
        content: 'test',
        imagePath: file.path,
        imageBase64: null,
      );

      expect(msg.decodedImageBytes, isNotNull);
      expect(msg.decodedImageBytes!.length, bytes.length);
      expect(msg.decodedImageBytes, bytes);

      await dir.delete(recursive: true);
    });

    test('decodedImageBytes prefers base64 over file', () async {
      final dir = await Directory.systemTemp.createTemp('clm_test2_');
      final file = File('${dir.path}/test2.png');
      final fileBytes = Uint8List.fromList([1, 2, 3]);
      await file.writeAsBytes(fileBytes);

      // base64 for [4,5,6]
      const b64 = 'BAUG'; // base64 of [4,5,6]
      final msg = ChatMessage(
        id: 'test-id2',
        chatId: 'chat-1',
        role: 'assistant',
        content: 'test',
        imageBase64: b64,
        imagePath: file.path,
      );

      expect(msg.decodedImageBytes, Uint8List.fromList([4, 5, 6]));
      await dir.delete(recursive: true);
    });

    test('decodedImageBytes returns null when both missing', () {
      final msg = ChatMessage(
        id: 'id',
        chatId: 'chat-1',
        role: 'user',
        content: 'hello',
      );
      expect(msg.decodedImageBytes, isNull);
    });
  });
}
