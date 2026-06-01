import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/points.dart';
import '../../services/points_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';

class PointsScreen extends StatefulWidget {
  const PointsScreen({
    super.key,
    this.pointsService = const PointsService(),
  });

  final PointsService pointsService;

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  final TextEditingController _codeController = TextEditingController();
  late Future<_PointsPageData> _future;
  bool _redeeming = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _future = _loadDeferred();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<_PointsPageData> _load() async {
    final balance = await widget.pointsService.fetchBalance();
    final ledger = await widget.pointsService.fetchLedger(limit: 20);
    return _PointsPageData(balance, ledger);
  }

  Future<_PointsPageData> _loadDeferred() => Future.microtask(_load);

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
      setState(() => _codeError = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _redeeming = false);
      }
    }
  }

  bool _isValidCode(String code) {
    return RegExp(r'^[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}-[A-HJ-KM-NP-Z2-9]{4}$')
        .hasMatch(code);
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
                          .map((entry) => '${_featureLabel(entry.key)} ${entry.value}')
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
  const _PointsPageData(this.balance, this.ledger);

  final PointsBalance balance;
  final List<PointsLedgerEntry> ledger;
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
