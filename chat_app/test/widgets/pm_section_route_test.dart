import 'package:chat_app/widgets/pm_navigation_rail.dart';
import 'package:chat_app/widgets/pm_section_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _section(String name) => Scaffold(
      body: Row(children: [
        PMNavigationRail(selectedIndex: 0, onSelected: (_) {}),
        Expanded(child: Center(child: Text(name))),
      ]),
    );

void main() {
  testWidgets(
      'desktop push, replace, pop and section switch stay fixed each frame',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      onGenerateRoute: (settings) => PMSectionRoute<void>(
        stationary: true,
        settings: settings,
        builder: (_) => _section(settings.name ?? '/'),
      ),
      initialRoute: '/',
    ));
    final railBounds = tester.getRect(find.byType(PMNavigationRail));
    Future<void> checkFrames(String route) async {
      // Do not pumpAndSettle: the regression only exists in intermediate frames.
      for (var frame = 0; frame < 28; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(PMNavigationRail), findsOneWidget);
        expect(tester.getRect(find.byType(PMNavigationRail)), railBounds,
            reason: '$route frame $frame');
        expect(find.text(route), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }

    navigator.currentState!.pushNamed('/chat/1');
    await checkFrames('/chat/1');
    navigator.currentState!.pushReplacementNamed('/chat/2');
    await checkFrames('/chat/2');
    navigator.currentState!.pop();
    await checkFrames('/');
    navigator.currentState!.pushNamed('/chat/1');
    await checkFrames('/chat/1');
    navigator.currentState!
        .pushNamedAndRemoveUntil('/home/contacts', (_) => false);
    await checkFrames('/home/contacts');
  });

  testWidgets('compact navigation retains the platform transition',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: _section('home')));
    final route = PMSectionRoute<void>(
        stationary: false, builder: (_) => _section('chat'));
    navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.transitionDuration, greaterThan(Duration.zero));
    expect(route.animation!.value, allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(find.text('chat'), findsOneWidget);
  });
}
