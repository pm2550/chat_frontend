import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';

/// Basic smoke test to verify core models can be instantiated
void main() {
  test('Core models can be instantiated', () {
    final user = User(
      id: '1',
      username: 'test',
      email: 'test@example.com',
      displayName: 'Test User',
      createdAt: DateTime.now(),
    );
    expect(user.username, 'test');

    final chat = Chat(
      id: '1',
      name: 'Test Chat',
      createdAt: DateTime.now(),
    );
    expect(chat.name, 'Test Chat');

    final message = Message(
      id: '1',
      content: 'Hello',
      chatRoomId: '1',
      senderId: '1',
      senderName: 'Test User',
      timestamp: DateTime.now(),
    );
    expect(message.content, 'Hello');
  });
}
