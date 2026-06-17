import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/points.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/points_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';

class PointsScreen extends StatefulWidget {
  const PointsScreen({
    super.key,
    this.pointsService = const PointsService(),
    this.authService,
    this.isAdminOverride,
  });

  final PointsService pointsService;
  final AuthService? authService;
  final bool? isAdminOverride;

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _adminUserController = TextEditingController();
  final TextEditingController _adminPointsController =
      TextEditingController(text: '100');
  final TextEditingController _adminMemoController = TextEditingController();
  final TextEditingController _issueCountController =
      TextEditingController(text: '5');
  final TextEditingController _issuePointsController =
      TextEditingController(text: '100');
  final TextEditingController _issueBatchController = TextEditingController();
  final TextEditingController _issueMemoController = TextEditingController();
  late Future<_PointsPageData> _future;
  bool _redeeming = false;
  String? _codeError;
  bool _adminSearching = false;
  bool _adminAdjusting = false;
  bool _issuingCodes = false;
  String? _adminError;
  String? _issueError;
  List<User> _adminSearchResults = const [];
  User? _selectedAdminUser;
  PointsBalance? _selectedAdminBalance;
  List<PointsLedgerEntry> _selectedAdminLedger = const [];
  List<String> _issuedCodes = const [];

  @override
  void initState() {
    super.initState();
    _future = _loadDeferred();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _adminUserController.dispose();
    _adminPointsController.dispose();
    _adminMemoController.dispose();
    _issueCountController.dispose();
    _issuePointsController.dispose();
    _issueBatchController.dispose();
    _issueMemoController.dispose();
    super.dispose();
  }

  Future<_PointsPageData> _load() async {
    final balance = await widget.pointsService.fetchBalance();
    final ledger = await widget.pointsService.fetchLedger(limit: 20);
    final canUseAdminTools = await _detectAdminAccess();
    return _PointsPageData(balance, ledger, canUseAdminTools);
  }

  Future<_PointsPageData> _loadDeferred() => Future.microtask(_load);

  AuthService get _auth => widget.authService ?? AuthService();

  void _refresh() {
    setState(() {
      _future = _loadDeferred();
    });
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim().toUpperCase();
    if (!_isValidCode(code)) {
      setState(() => _codeError = '请输入 XXXX-XXXX-XXXX 格式的兑换码');
      return;
    }
    setState(() {
      _redeeming = true;
      _codeError = null;
    });
    try {
      final result = await widget.pointsService.redeem(code);
      if (!mounted) return;
      _codeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功兑换 ${result.credited} 积分')),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(
          () => _codeError = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _redeeming = false);
      }
    }
  }

  bool _isValidCode(String code) {
    return RegExp(
            r'^[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}$')
        .hasMatch(code);
  }

  Future<bool> _detectAdminAccess() async {
    final override = widget.isAdminOverride;
    if (override != null) return override;
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    if (currentUser.roles.contains(UserRole.admin)) return true;
    try {
      await widget.pointsService.adminFetchUserBalance(currentUser.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _searchAdminUsers() async {
    final keyword = _adminUserController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _adminSearchResults = const [];
        _adminError = '请输入用户名、昵称或邮箱';
      });
      return;
    }
    setState(() {
      _adminSearching = true;
      _adminError = null;
    });
    try {
      final users = await widget.pointsService.searchUsers(keyword, limit: 8);
      if (!mounted) return;
      setState(() {
        _adminSearchResults = users;
        if (users.isEmpty) {
          _adminError = '没有找到匹配用户';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _adminError = _cleanError(error));
    } finally {
      if (mounted) setState(() => _adminSearching = false);
    }
  }

  Future<void> _selectAdminUser(User user) async {
    setState(() {
      _selectedAdminUser = user;
      _adminSearchResults = const [];
      _adminUserController.text = user.displayName.isNotEmpty
          ? '${user.displayName} (${user.username})'
          : user.username;
      _adminError = null;
    });
    await _loadSelectedAdminUser();
  }

  Future<void> _loadSelectedAdminUser() async {
    final user = _selectedAdminUser;
    if (user == null) return;
    setState(() => _adminAdjusting = true);
    try {
      final results = await Future.wait([
        widget.pointsService.adminFetchUserBalance(user.id),
        widget.pointsService.adminFetchUserLedger(user.id, limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _selectedAdminBalance = results[0] as PointsBalance;
        _selectedAdminLedger = results[1] as List<PointsLedgerEntry>;
        _adminError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _adminError = _cleanError(error));
    } finally {
      if (mounted) setState(() => _adminAdjusting = false);
    }
  }

  Future<void> _adjustSelectedUser({required bool credit}) async {
    final user = _selectedAdminUser;
    if (user == null) {
      setState(() => _adminError = '请先选择用户');
      return;
    }
    final points = int.tryParse(_adminPointsController.text.trim()) ?? 0;
    if (points <= 0) {
      setState(() => _adminError = '积分数量必须大于 0');
      return;
    }
    setState(() {
      _adminAdjusting = true;
      _adminError = null;
    });
    try {
      final balance = credit
          ? await widget.pointsService.adminCreditUser(
              user.id,
              points,
              memo: _adminMemoController.text,
            )
          : await widget.pointsService.adminDebitUser(
              user.id,
              points,
              memo: _adminMemoController.text,
            );
      final ledger =
          await widget.pointsService.adminFetchUserLedger(user.id, limit: 8);
      if (!mounted) return;
      setState(() {
        _selectedAdminBalance = balance;
        _selectedAdminLedger = ledger;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(credit ? '已加 $points 积分' : '已扣 $points 积分')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _adminError = _cleanError(error));
    } finally {
      if (mounted) setState(() => _adminAdjusting = false);
    }
  }

  Future<void> _issueCodes() async {
    final count = int.tryParse(_issueCountController.text.trim()) ?? 0;
    final pointsEach = int.tryParse(_issuePointsController.text.trim()) ?? 0;
    if (count <= 0 || pointsEach <= 0) {
      setState(() => _issueError = '数量和每码积分都必须大于 0');
      return;
    }
    setState(() {
      _issuingCodes = true;
      _issueError = null;
      _issuedCodes = const [];
    });
    try {
      final result = await widget.pointsService.adminIssueCodes(
        count: count,
        pointsEach: pointsEach,
        batchLabel: _issueBatchController.text,
        memo: _issueMemoController.text,
      );
      if (!mounted) return;
      setState(() => _issuedCodes = result.codes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成 ${result.codes.length} 个兑换码')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _issueError = _cleanError(error));
    } finally {
      if (mounted) setState(() => _issuingCodes = false);
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PMBreakpoints.isDesktop(context)
          ? null
          : AppBar(title: const Text('我的积分')),
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: FutureBuilder<_PointsPageData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(PMSpacing.xl),
                      child: PMErrorState(
                        title: '积分信息加载失败',
                        message: snapshot.error.toString(),
                        onRetry: _refresh,
                      ),
                    );
                  }
                  final data = snapshot.data ??
                      const _PointsPageData(
                        PointsBalance(
                          freeRemainingPerFeature: {},
                          paidPoints: 0,
                        ),
                        [],
                        false,
                      );
                  return _buildContent(data);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_PointsPageData data) {
    return ListView(
      padding: const EdgeInsets.all(PMSpacing.xl),
      children: [
        PMPageHeader(
          title: '我的积分',
          subtitle: '查看免费额度、付费积分和最近使用记录',
          leading: _heroIcon(),
          actions: [
            PMButton(
              label: '刷新',
              icon: Icons.refresh,
              onPressed: _refresh,
              variant: PMButtonVariant.secondary,
              compact: true,
            ),
            if (PMBreakpoints.isDesktop(context))
              PMButton(
                label: '返回',
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(context).maybePop(),
                variant: PMButtonVariant.secondary,
                compact: true,
              ),
          ],
        ),
        const SizedBox(height: PMSpacing.xl),
        _buildBalanceCard(data.balance),
        const SizedBox(height: PMSpacing.l),
        _buildRedeemCard(),
        const SizedBox(height: PMSpacing.l),
        _buildLedgerCard(data.ledger),
        if (data.canUseAdminTools) ...[
          const SizedBox(height: PMSpacing.l),
          _buildAdminToolsCard(),
        ],
      ],
    );
  }

  Widget _heroIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        gradient: AppColors.messageGradient,
        borderRadius: BorderRadius.circular(PMRadius.m),
        boxShadow: const [PMElevation.card],
      ),
      child: const Icon(Icons.toll, color: Colors.white, size: 28),
    );
  }

  Widget _buildBalanceCard(PointsBalance balance) {
    final totalFree = balance.freeRemainingPerFeature.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '积分余额',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: PMSpacing.l),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final tiles = [
                _StatTile(
                  label: '免费额度今日剩余',
                  value: '$totalFree 次',
                  color: AppColors.secondary,
                  subtitle: balance.freeRemainingPerFeature.isEmpty
                      ? '暂无免费功能配置'
                      : balance.freeRemainingPerFeature.entries
                          .map((entry) =>
                              '${_featureLabel(entry.key)} ${entry.value}')
                          .join(' · '),
                ),
                _StatTile(
                  label: '付费积分',
                  value: '${balance.paidPoints}',
                  color: AppColors.primary,
                  subtitle: '兑换码充值后立即到账',
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    tiles[0],
                    const SizedBox(height: PMSpacing.m),
                    tiles[1],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: PMSpacing.m),
                  Expanded(child: tiles[1]),
                ],
              );
            },
          ),
          const SizedBox(height: PMSpacing.m),
          const Text(
            '免费额度按功能分别统计，每日 00:00 自动重置；付费积分不会自动过期。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildRedeemCard() {
    return PMSectionCard(
      title: '兑换码',
      subtitle: '管理员收款后会给你一个 12 位兑换码，只可使用一次。',
      children: [
        Padding(
          padding: const EdgeInsets.all(PMSpacing.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
                    UpperCaseTextFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: 'XXXX-XXXX-XXXX',
                    labelText: '兑换码',
                    errorText: _codeError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PMRadius.s),
                    ),
                  ),
                  onSubmitted: (_) => _redeeming ? null : _redeem(),
                ),
              ),
              const SizedBox(width: PMSpacing.m),
              PMButton(
                label: '兑换',
                icon: Icons.redeem,
                loading: _redeeming,
                onPressed: _redeeming ? null : _redeem,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLedgerCard(List<PointsLedgerEntry> ledger) {
    if (ledger.isEmpty) {
      return const PMSectionCard(
        title: '最近 20 条记录',
        subtitle: '兑换和使用记录会显示在这里。',
        children: [
          Padding(
            padding: EdgeInsets.all(PMSpacing.l),
            child: PMEmptyState(
              icon: Icons.receipt_long_outlined,
              title: '暂无积分记录',
              variant: EmptyStateVariant.muted,
            ),
          ),
        ],
      );
    }
    return PMSectionCard(
      title: '最近 20 条记录',
      subtitle: '账本只追加记录，方便核对兑换、扣除和退款。',
      children: [
        for (final entry in ledger)
          PMListRow(
            leading: _ledgerIcon(entry),
            title: Text(_reasonLabel(entry.reason)),
            subtitle: Text([
              if (entry.refKey != null) _featureLabel(entry.refKey!),
              if (entry.memo != null && entry.memo!.isNotEmpty) entry.memo!,
              if (entry.createdAt != null) _formatTime(entry.createdAt!),
            ].join(' · ')),
            trailing: Text(
              entry.delta > 0
                  ? '+${entry.delta}'
                  : entry.delta < 0
                      ? '${entry.delta}'
                      : entry.freeUsed > 0
                          ? '免费 -${entry.freeUsed} 次'
                          : '0',
              style: TextStyle(
                color: entry.delta >= 0 ? AppColors.success : AppColors.warning,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAdminToolsCard() {
    return PMSectionCard(
      title: '管理员积分管理',
      subtitle: '查看用户积分、手动加减积分，或批量发放一次性兑换码。',
      children: [
        Padding(
          padding: const EdgeInsets.all(PMSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAdminUserSearch(),
              if (_adminError != null) ...[
                const SizedBox(height: PMSpacing.s),
                Text(
                  _adminError!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_adminSearchResults.isNotEmpty) ...[
                const SizedBox(height: PMSpacing.m),
                _buildAdminSearchResults(),
              ],
              if (_selectedAdminUser != null) ...[
                const SizedBox(height: PMSpacing.l),
                _buildSelectedUserPanel(),
              ],
              const SizedBox(height: PMSpacing.xl),
              _buildIssueCodesPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdminUserSearch() {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final input = TextField(
      controller: _adminUserController,
      decoration: InputDecoration(
        labelText: '搜索用户',
        hintText: '用户名、昵称或邮箱',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PMRadius.s),
        ),
      ),
      onSubmitted: (_) => _adminSearching ? null : _searchAdminUsers(),
    );
    final button = PMButton(
      label: '搜索',
      icon: Icons.search,
      loading: _adminSearching,
      onPressed: _adminSearching ? null : _searchAdminUsers,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          input,
          const SizedBox(height: PMSpacing.m),
          button,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: input),
        const SizedBox(width: PMSpacing.m),
        button,
      ],
    );
  }

  Widget _buildAdminSearchResults() {
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.s),
      child: Column(
        children: [
          for (final user in _adminSearchResults)
            PMListRow(
              leading: PMUserAvatar(user: user, size: 38),
              title: Text(user.displayName.isNotEmpty
                  ? user.displayName
                  : user.username),
              subtitle: Text('@${user.username} · ${user.email}'),
              onTap: () => _selectAdminUser(user),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedUserPanel() {
    final user = _selectedAdminUser!;
    final balance = _selectedAdminBalance;
    final compact = MediaQuery.sizeOf(context).width < 720;
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PMUserAvatar(
                user: user,
                size: 44,
              ),
              const SizedBox(width: PMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName.isNotEmpty
                          ? user.displayName
                          : user.username,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '@${user.username} · ID ${user.id}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_adminAdjusting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: PMSpacing.l),
          _StatTile(
            label: '当前付费积分',
            value: '${balance?.paidPoints ?? 0}',
            color: AppColors.primary,
            subtitle: balance == null ? '正在读取余额' : '管理员可手动加减',
          ),
          const SizedBox(height: PMSpacing.l),
          compact ? _buildAdjustFormCompact() : _buildAdjustFormWide(),
          const SizedBox(height: PMSpacing.l),
          const Text(
            '最近调整',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          if (_selectedAdminLedger.isEmpty)
            const Text(
              '暂无积分记录',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            for (final entry in _selectedAdminLedger.take(5))
              PMListRow(
                dense: true,
                leading: _ledgerIcon(entry),
                title: Text(_reasonLabel(entry.reason)),
                subtitle: Text([
                  if (entry.memo != null && entry.memo!.isNotEmpty) entry.memo!,
                  if (entry.createdAt != null) _formatTime(entry.createdAt!),
                ].join(' · ')),
                trailing: Text(
                  entry.delta > 0 ? '+${entry.delta}' : '${entry.delta}',
                  style: TextStyle(
                    color: entry.delta >= 0
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAdjustFormCompact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPointsField(),
        const SizedBox(height: PMSpacing.m),
        _buildMemoField(),
        const SizedBox(height: PMSpacing.m),
        Row(
          children: [
            Expanded(child: _buildCreditButton()),
            const SizedBox(width: PMSpacing.m),
            Expanded(child: _buildDebitButton()),
          ],
        ),
      ],
    );
  }

  Widget _buildAdjustFormWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 140, child: _buildPointsField()),
        const SizedBox(width: PMSpacing.m),
        Expanded(child: _buildMemoField()),
        const SizedBox(width: PMSpacing.m),
        _buildCreditButton(),
        const SizedBox(width: PMSpacing.s),
        _buildDebitButton(),
      ],
    );
  }

  Widget _buildPointsField() {
    return TextField(
      controller: _adminPointsController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: '积分',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PMRadius.s),
        ),
      ),
    );
  }

  Widget _buildMemoField() {
    return TextField(
      controller: _adminMemoController,
      decoration: InputDecoration(
        labelText: '备注',
        hintText: '例如 手动补发 / 退款',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PMRadius.s),
        ),
      ),
    );
  }

  Widget _buildCreditButton() {
    return PMButton(
      label: '加积分',
      icon: Icons.add,
      loading: _adminAdjusting,
      onPressed:
          _adminAdjusting ? null : () => _adjustSelectedUser(credit: true),
    );
  }

  Widget _buildDebitButton() {
    return PMButton(
      label: '扣积分',
      icon: Icons.remove,
      variant: PMButtonVariant.danger,
      loading: _adminAdjusting,
      onPressed:
          _adminAdjusting ? null : () => _adjustSelectedUser(credit: false),
    );
  }

  Widget _buildIssueCodesPanel() {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final fields = [
      SizedBox(
          width: 110, child: _smallNumberField(_issueCountController, '数量')),
      SizedBox(
        width: 130,
        child: _smallNumberField(_issuePointsController, '每码积分'),
      ),
      Expanded(
        child: TextField(
          controller: _issueBatchController,
          decoration: InputDecoration(
            labelText: '批次',
            hintText: '例如 2026-06 活动',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PMRadius.s),
            ),
          ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '发兑换码',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: PMSpacing.s),
        const Text(
          '生成的明文兑换码只会显示这一次，请立即分发或保存到你的离线记录。',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: PMSpacing.m),
        compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: PMSpacing.m),
                    Expanded(child: fields[1])
                  ]),
                  const SizedBox(height: PMSpacing.m),
                  fields[2],
                ],
              )
            : Row(
                children: [
                  fields[0],
                  const SizedBox(width: PMSpacing.m),
                  fields[1],
                  const SizedBox(width: PMSpacing.m),
                  fields[2],
                ],
              ),
        const SizedBox(height: PMSpacing.m),
        TextField(
          controller: _issueMemoController,
          decoration: InputDecoration(
            labelText: '兑换备注',
            hintText: '用户兑换后可在账本里看到',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PMRadius.s),
            ),
          ),
        ),
        if (_issueError != null) ...[
          const SizedBox(height: PMSpacing.s),
          Text(
            _issueError!,
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: PMSpacing.m),
        PMButton(
          label: '生成兑换码',
          icon: Icons.confirmation_number_outlined,
          loading: _issuingCodes,
          onPressed: _issuingCodes ? null : _issueCodes,
        ),
        if (_issuedCodes.isNotEmpty) ...[
          const SizedBox(height: PMSpacing.m),
          PMCard(
            padding: const EdgeInsets.all(PMSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '本次生成的兑换码',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    PMButton(
                      label: '复制全部',
                      icon: Icons.copy,
                      compact: true,
                      variant: PMButtonVariant.secondary,
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _issuedCodes.join('\n')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.s),
                SelectableText(
                  _issuedCodes.join('\n'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _smallNumberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PMRadius.s),
        ),
      ),
    );
  }

  Widget _ledgerIcon(PointsLedgerEntry entry) {
    final reason = _normalizedKey(entry.reason);
    final isCredit = entry.delta > 0 || reason == 'feature_refund';
    final color = isCredit
        ? AppColors.success
        : entry.delta < 0
            ? AppColors.warning
            : AppColors.primary;
    final icon = reason == 'feature_refund'
        ? Icons.undo
        : isCredit
            ? Icons.add
            : Icons.remove;
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.subtitle,
  });

  final String label;
  final String value;
  final Color color;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PMSpacing.l),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PMRadius.m),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointsPageData {
  const _PointsPageData(
    this.balance,
    this.ledger,
    this.canUseAdminTools,
  );

  final PointsBalance balance;
  final List<PointsLedgerEntry> ledger;
  final bool canUseAdminTools;
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

String _reasonLabel(String reason) {
  return switch (_normalizedKey(reason)) {
    'redeem_code' => '兑换码充值',
    'feature_debit' => '功能使用',
    'feature_refund' => '失败退款',
    'admin_credit' => '管理员加点',
    'admin_debit' => '管理员扣点',
    'daily_grant' => '每日额度',
    _ => reason,
  };
}

String _featureLabel(String key) {
  return switch (_normalizedKey(key)) {
    'ai_image_gen' => 'AI 出图',
    'bot_invoke_official' => '官方模型 Bot',
    'test_debit' => '测试扣点',
    'redemption_code' => '兑换码',
    'admin_adjustment' => '管理员调整',
    _ => key,
  };
}

String _normalizedKey(String value) => value.trim().toLowerCase();

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
