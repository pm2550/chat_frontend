import 'package:chat_app/models/points.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/settings/points_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/points_service.dart';
import 'package:chat_app/widgets/cost_preview_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  group('PointsScreen', () {
    testWidgets('renders balance, free quota and ledger rows', (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final service = _FakePointsService(
        balance: const PointsBalance(
          paidPoints: 47,
          freeRemainingPerFeature: {
            'ai_image_gen': 3,
            'test_debit': 2,
          },
        ),
        ledger: const [
          PointsLedgerEntry(
            id: 1,
            delta: 100,
            reason: 'redeem_code',
            refKey: 'redemption_code',
            refId: 'code-1',
            balancePaidAfter: 147,
            freeUsed: 0,
            memo: '首充',
          ),
          PointsLedgerEntry(
            id: 2,
            delta: 0,
            reason: 'feature_debit',
            refKey: 'test_debit',
            refId: 'smoke',
            balancePaidAfter: 147,
            freeUsed: 1,
            freeRemainingAfter: 1,
            memo: 'free smoke',
          ),
        ],
      );

      await tester.pumpWidget(harness(PointsScreen(pointsService: service)));
      await tester.pumpAndSettle();

      expect(find.text('我的积分'), findsWidgets);
      expect(find.text('47'), findsOneWidget);
      expect(find.text('5 次'), findsOneWidget);
      expect(find.text('兑换码充值'), findsOneWidget);
      expect(find.text('功能使用'), findsOneWidget);
      expect(find.textContaining('首充'), findsOneWidget);
      expect(find.text('免费 -1 次'), findsOneWidget);
    });

    testWidgets('shows validation error for malformed redemption code',
        (tester) async {
      final service = _FakePointsService();

      await tester.pumpWidget(harness(PointsScreen(pointsService: service)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.widgetWithText(FilledButton, '兑换'));
      await tester.pump();

      expect(find.text('请输入 XXXX-XXXX-XXXX 格式的兑换码'), findsOneWidget);
      expect(service.redeemCalls, 0);
    });

    testWidgets('redeems a valid code and refreshes balance', (tester) async {
      final service = _FakePointsService(
        balance: const PointsBalance(
          paidPoints: 0,
          freeRemainingPerFeature: {'test_debit': 1},
        ),
        redeemResult: const RedeemResult(
          credited: 100,
          newPaidBalance: 100,
          codeMemo: 'top-up',
        ),
      );

      await tester.pumpWidget(harness(PointsScreen(pointsService: service)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ABCD-EFGH-2345');
      await tester.tap(find.widgetWithText(FilledButton, '兑换'));
      await tester.pumpAndSettle();

      expect(service.redeemCalls, 1);
      expect(service.lastRedeemedCode, 'ABCD-EFGH-2345');
      expect(service.balanceFetches, 2);
      expect(find.text('成功兑换 100 积分'), findsOneWidget);
    });

    testWidgets('renders empty ledger state', (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final service = _FakePointsService(
        balance: const PointsBalance(
          paidPoints: 0,
          freeRemainingPerFeature: {},
        ),
      );

      await tester.pumpWidget(harness(PointsScreen(pointsService: service)));
      await tester.pumpAndSettle();

      expect(find.text('暂无积分记录'), findsOneWidget);
      expect(find.text('暂无免费功能配置'), findsOneWidget);
    });

    testWidgets('admin tools search users, credit points and issue codes',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final service = _FakePointsService(
        users: [_adminTarget],
        adminBalance: const PointsBalance(
          paidPoints: 20,
          freeRemainingPerFeature: {},
        ),
        adminLedger: const [
          PointsLedgerEntry(
            id: 10,
            delta: 20,
            reason: 'admin_credit',
            balancePaidAfter: 20,
            freeUsed: 0,
            memo: 'seed',
          ),
        ],
        issueCodesResult:
            const IssueCodesResult(codes: ['ABCD-EFGH-2345', 'JKLM-NPQR-6789']),
      );

      await tester.pumpWidget(
        harness(
          PointsScreen(
            pointsService: service,
            isAdminOverride: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('管理员积分管理'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '搜索用户'),
        'target',
      );
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pumpAndSettle();

      expect(service.searchCalls, 1);
      expect(find.text('Target User'), findsOneWidget);

      await tester.tap(find.text('Target User').first);
      await tester.pumpAndSettle();

      expect(service.adminBalanceFetches, 1);
      expect(find.text('当前付费积分'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '积分'), '30');
      await tester.enterText(find.widgetWithText(TextField, '备注'), 'manual');
      await tester.tap(find.widgetWithText(FilledButton, '加积分'));
      await tester.pumpAndSettle();

      expect(service.adminCreditCalls, 1);
      expect(service.lastAdjustedUserId, '42');
      expect(service.lastAdjustedPoints, 30);

      await tester.tap(find.widgetWithText(FilledButton, '生成兑换码'));
      await tester.pumpAndSettle();

      expect(service.issueCalls, 1);
      expect(find.text('ABCD-EFGH-2345\nJKLM-NPQR-6789'), findsOneWidget);
    });

    testWidgets('admin tools show when backend admin probe succeeds',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final service = _FakePointsService(
        balance: const PointsBalance(
          paidPoints: 0,
          freeRemainingPerFeature: {},
        ),
        adminBalance: const PointsBalance(
          paidPoints: 10000,
          freeRemainingPerFeature: {},
        ),
      );

      await tester.pumpWidget(
        harness(
          PointsScreen(
            pointsService: service,
            authService: _FakeAuthService(
              currentUser: User(
                id: '1',
                username: 'admin',
                email: 'admin@example.com',
                displayName: 'Admin',
                createdAt: DateTime(2026, 1, 1),
                roles: const [UserRole.user],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.adminBalanceFetches, 1);
      expect(find.text('管理员积分管理'), findsOneWidget);
    });
  });

  group('PMCostPreviewChip', () {
    testWidgets('shows free quota cost preview', (tester) async {
      final service = _FakePointsService(
        preview: const CostPreview(
          featureKey: 'test_debit',
          cost: 1,
          freeRemaining: 3,
          willUseFree: true,
          paidPoints: 47,
          paidRemainingAfter: 47,
          sufficient: true,
        ),
      );

      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Center(
              child: PMCostPreviewChip(
                featureKey: 'test_debit',
                pointsService: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('本次免费 · 今日剩余 3 次'), findsOneWidget);
    });

    testWidgets('shows paid cost preview and projected balance',
        (tester) async {
      final service = _FakePointsService(
        preview: const CostPreview(
          featureKey: 'ai_image_gen',
          cost: 10,
          freeRemaining: 0,
          willUseFree: false,
          paidPoints: 47,
          paidRemainingAfter: 37,
          sufficient: true,
        ),
      );

      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Center(
              child: PMCostPreviewChip(
                featureKey: 'ai_image_gen',
                pointsService: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('本次 10 积分 · 余额 47 → 37'), findsOneWidget);
    });
  });
}

class _FakePointsService extends PointsService {
  _FakePointsService({
    this.balance = const PointsBalance(
      paidPoints: 0,
      freeRemainingPerFeature: {},
    ),
    this.ledger = const <PointsLedgerEntry>[],
    this.preview = const CostPreview(
      featureKey: 'test_debit',
      cost: 1,
      freeRemaining: 0,
      willUseFree: false,
      paidPoints: 0,
      paidRemainingAfter: 0,
      sufficient: false,
    ),
    this.redeemResult = const RedeemResult(
      credited: 0,
      newPaidBalance: 0,
    ),
    this.users = const <User>[],
    this.adminBalance = const PointsBalance(
      paidPoints: 0,
      freeRemainingPerFeature: {},
    ),
    this.adminLedger = const <PointsLedgerEntry>[],
    this.issueCodesResult = const IssueCodesResult(codes: []),
  });

  final PointsBalance balance;
  final List<PointsLedgerEntry> ledger;
  final CostPreview preview;
  final RedeemResult redeemResult;
  final List<User> users;
  PointsBalance adminBalance;
  List<PointsLedgerEntry> adminLedger;
  final IssueCodesResult issueCodesResult;

  int balanceFetches = 0;
  int ledgerFetches = 0;
  int redeemCalls = 0;
  int searchCalls = 0;
  int adminBalanceFetches = 0;
  int adminLedgerFetches = 0;
  int adminCreditCalls = 0;
  int adminDebitCalls = 0;
  int issueCalls = 0;
  String? lastRedeemedCode;
  String? lastAdjustedUserId;
  int? lastAdjustedPoints;

  @override
  Future<PointsBalance> fetchBalance() async {
    balanceFetches += 1;
    return balance;
  }

  @override
  Future<List<PointsLedgerEntry>> fetchLedger({
    int limit = 20,
    int offset = 0,
  }) async {
    ledgerFetches += 1;
    return ledger;
  }

  @override
  Future<CostPreview> previewCost(String featureKey) async {
    return preview;
  }

  @override
  Future<RedeemResult> redeem(String code) async {
    redeemCalls += 1;
    lastRedeemedCode = code;
    return redeemResult;
  }

  @override
  Future<List<User>> searchUsers(String keyword, {int limit = 10}) async {
    searchCalls += 1;
    return users;
  }

  @override
  Future<PointsBalance> adminFetchUserBalance(String userId) async {
    adminBalanceFetches += 1;
    return adminBalance;
  }

  @override
  Future<List<PointsLedgerEntry>> adminFetchUserLedger(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    adminLedgerFetches += 1;
    return adminLedger;
  }

  @override
  Future<PointsBalance> adminCreditUser(
    String userId,
    int points, {
    String? memo,
  }) async {
    adminCreditCalls += 1;
    lastAdjustedUserId = userId;
    lastAdjustedPoints = points;
    adminBalance = PointsBalance(
      paidPoints: adminBalance.paidPoints + points,
      freeRemainingPerFeature: adminBalance.freeRemainingPerFeature,
    );
    return adminBalance;
  }

  @override
  Future<PointsBalance> adminDebitUser(
    String userId,
    int points, {
    String? memo,
  }) async {
    adminDebitCalls += 1;
    lastAdjustedUserId = userId;
    lastAdjustedPoints = points;
    adminBalance = PointsBalance(
      paidPoints: adminBalance.paidPoints - points,
      freeRemainingPerFeature: adminBalance.freeRemainingPerFeature,
    );
    return adminBalance;
  }

  @override
  Future<IssueCodesResult> adminIssueCodes({
    required int count,
    required int pointsEach,
    String? batchLabel,
    String? memo,
  }) async {
    issueCalls += 1;
    return issueCodesResult;
  }
}

final _adminTarget = User(
  id: '42',
  username: 'target',
  email: 'target@example.com',
  displayName: 'Target User',
  createdAt: DateTime(2026, 1, 1),
  roles: const [UserRole.user],
);

class _FakeAuthService extends AuthService {
  _FakeAuthService({required User currentUser})
      : _currentUser = currentUser,
        super.test();

  final User _currentUser;

  @override
  User? get currentUser => _currentUser;
}
