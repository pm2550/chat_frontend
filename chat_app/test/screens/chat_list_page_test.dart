import 'dart:async';
import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/constants/app_colors.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/chat_list_page.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/desktop_notification_service.dart';
import 'package:chat_app/services/desktop_notification_stub.dart';
import 'package:chat_app/services/notification_tap_router.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

part 'sub/chat_list_page_test_cases_1.dart';
part 'sub/chat_list_page_test_cases_2.dart';
part 'sub/chat_list_page_test_fixtures_1.dart';

Widget buildTestWidget(
  ChatDataService service, {
  FakeRealtimeService? realtimeService,
  DesktopNotificationService? notificationService,
  String currentUserId = 'me',
}) {
  return MaterialApp(
    routes: {
      '/chat': (context) => const Scaffold(body: Text('Chat Page')),
    },
    home: ChatListPage(
      chatService: service,
      realtimeService: realtimeService ?? FakeRealtimeService(),
      notificationService: notificationService,
      currentUserId: currentUserId,
    ),
  );
}

void main() {
  group('ChatListPage', () {
    _chatListCases1();
    _chatListCases2();
  });
}
