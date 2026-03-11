import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/screens/auth/login_screen.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      routes: {
        '/register': (context) => const Scaffold(body: Text('Register Page')),
        '/home': (context) => const Scaffold(body: Text('Home Page')),
      },
      home: const LoginScreen(),
    );
  }

  // LoginScreen has a tall Column layout that overflows in the default
  // 800x600 test surface. Give it a phone-sized viewport.
  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
  }

  group('LoginScreen', () {
    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.clearAllTestValues();
    });

    testWidgets('renders app title "聊天应用"', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('聊天应用'), findsOneWidget);
    });

    testWidgets('renders welcome text "欢迎回来"', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('欢迎回来'), findsOneWidget);
    });

    testWidgets('renders username text field with label "用户名"',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('用户名'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('renders password text field with label "密码"',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('密码'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('renders login button with text "登录"', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('登录'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('renders register link "还没有账号？立即注册"', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('还没有账号？立即注册'), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('renders test account info', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('测试账号'), findsOneWidget);
    });

    testWidgets('renders chat icon', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
    });

    testWidgets('password field is initially obscured', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      final textFormFields = find.byType(TextFormField);
      expect(textFormFields, findsNWidgets(2));
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });

    testWidgets('password visibility toggle works', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });

    testWidgets('shows validation error when submitting empty form',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(find.text('请输入用户名'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
    });

    testWidgets(
        'shows only password validation error when username is filled',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.enterText(find.byType(TextFormField).first, 'testuser');
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(find.text('请输入用户名'), findsNothing);
      expect(find.text('请输入密码'), findsOneWidget);
    });

    testWidgets(
        'shows only username validation error when password is filled',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(find.text('请输入用户名'), findsOneWidget);
      expect(find.text('请输入密码'), findsNothing);
    });

    testWidgets('can enter text in username and password fields',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.enterText(find.byType(TextFormField).first, 'admin');
      await tester.enterText(find.byType(TextFormField).last, 'secret');
      expect(find.text('admin'), findsOneWidget);
      expect(find.text('secret'), findsOneWidget);
    });

    testWidgets('register link navigates to /register', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('还没有账号？立即注册'));
      await tester.pumpAndSettle();
      expect(find.text('Register Page'), findsOneWidget);
    });

    testWidgets('contains a Form widget with validation', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(Form), findsOneWidget);
    });
  });
}
