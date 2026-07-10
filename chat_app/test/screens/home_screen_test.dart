import 'package:chat_app/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeScreen tab cache', () {
    testWidgets('defers hidden cache warming until after the first frame',
        (tester) async {
      var warmCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cacheWarmupDelay: const Duration(milliseconds: 500),
            cacheWarmer: () async => warmCalls += 1,
            pageBuilder: (_, index, __) => Text('tab-$index'),
          ),
        ),
      );

      expect(warmCalls, 0);
      await tester.pump(const Duration(milliseconds: 499));
      expect(warmCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(warmCalls, 1);
    });

    testWidgets('keeps visited tabs alive when switching on mobile',
        (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(390, 844);
      view.devicePixelRatio = 1;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      final initCounts = <int, int>{};
      final disposeCounts = <int, int>{};

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            pageBuilder: (context, index, aiSection) {
              return _CountingTabPage(
                index: index,
                initCounts: initCounts,
                disposeCounts: disposeCounts,
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(initCounts, {0: 1});
      expect(disposeCounts, isEmpty);
      expect(find.text('tab-0'), findsOneWidget);

      await tester.tap(find.text('联系人'));
      await tester.pumpAndSettle();

      expect(initCounts[0], 1);
      expect(initCounts[1], 1);
      expect(disposeCounts[0], isNull);
      expect(find.text('tab-1'), findsOneWidget);

      await tester.tap(find.text('消息'));
      await tester.pumpAndSettle();

      expect(initCounts[0], 1);
      expect(initCounts[1], 1);
      expect(disposeCounts[0], isNull);
      expect(disposeCounts[1], isNull);
      expect(find.text('tab-0'), findsOneWidget);
    });
  });
}

class _CountingTabPage extends StatefulWidget {
  const _CountingTabPage({
    required this.index,
    required this.initCounts,
    required this.disposeCounts,
  });

  final int index;
  final Map<int, int> initCounts;
  final Map<int, int> disposeCounts;

  @override
  State<_CountingTabPage> createState() => _CountingTabPageState();
}

class _CountingTabPageState extends State<_CountingTabPage> {
  @override
  void initState() {
    super.initState();
    widget.initCounts
        .update(widget.index, (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.disposeCounts
        .update(widget.index, (count) => count + 1, ifAbsent: () => 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('tab-${widget.index}'));
  }
}
