import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/widgets/call_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildGrid(ChatCallState state) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 420,
          child: CallGridView(state: state),
        ),
      ),
    );
  }

  testWidgets('renders self as a one-up tile', (tester) async {
    await tester.pumpWidget(buildGrid(const ChatCallState(
      phase: CallPhase.connected,
      selfUserId: 1,
      participants: [
        CallParticipant(
          userId: 1,
          displayName: 'Alice',
          state: PeerConnectionState.connected,
        ),
      ],
    )));

    expect(find.text('Alice（我）'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
  });

  testWidgets('renders two participant labels for 1v1 layout', (tester) async {
    await tester.pumpWidget(buildGrid(const ChatCallState(
      phase: CallPhase.connected,
      selfUserId: 1,
      participants: [
        CallParticipant(userId: 1, displayName: 'Alice'),
        CallParticipant(
          userId: 2,
          displayName: 'Bob',
          state: PeerConnectionState.connected,
        ),
      ],
    )));

    expect(find.text('Alice（我）'), findsOneWidget);
    expect(find.text('Bob'), findsWidgets);
  });

  testWidgets('renders six participant mesh grid', (tester) async {
    await tester.pumpWidget(buildGrid(ChatCallState(
      phase: CallPhase.connected,
      selfUserId: 1,
      participants: List.generate(
        6,
        (index) => CallParticipant(
          userId: index + 1,
          displayName: 'Member ${index + 1}',
          state: PeerConnectionState.connected,
        ),
      ),
    )));

    expect(find.text('Member 1（我）'), findsOneWidget);
    expect(find.text('Member 6'), findsWidgets);
  });

  testWidgets('shows anonymous participant label and ring container',
      (tester) async {
    await tester.pumpWidget(buildGrid(const ChatCallState(
      phase: CallPhase.connected,
      selfUserId: 1,
      participants: [
        CallParticipant(userId: 1, displayName: 'Alice'),
        CallParticipant(
          userId: 2,
          displayName: '匿名访客',
          anonymous: true,
          anonymousTheme: 'night',
        ),
      ],
    )));

    expect(find.text('匿名访客'), findsWidgets);
  });

  testWidgets('shows muted and camera-off custom symbols', (tester) async {
    await tester.pumpWidget(buildGrid(const ChatCallState(
      phase: CallPhase.connected,
      mediaKind: CallMediaKind.video,
      selfUserId: 1,
      participants: [
        CallParticipant(
          userId: 1,
          displayName: 'Alice',
          micMuted: true,
          cameraOff: true,
        ),
      ],
    )));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is PMSymbolIcon && widget.symbol == PMSymbol.micOff,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is PMSymbolIcon && widget.symbol == PMSymbol.videoOff,
      ),
      findsOneWidget,
    );
    expect(find.text('摄像头已关'), findsOneWidget);
  });

  testWidgets('shows failed connection state badge', (tester) async {
    await tester.pumpWidget(buildGrid(const ChatCallState(
      phase: CallPhase.connected,
      selfUserId: 1,
      participants: [
        CallParticipant(userId: 1, displayName: 'Alice'),
        CallParticipant(
          userId: 2,
          displayName: 'Bob',
          state: PeerConnectionState.failed,
        ),
      ],
    )));

    expect(find.text('失败'), findsOneWidget);
  });
}
