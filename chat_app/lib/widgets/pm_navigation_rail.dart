import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../design/design.dart';
import 'pm_brand.dart';

class PMNavigationRail extends StatelessWidget {
  const PMNavigationRail(
      {super.key,
      required this.selectedIndex,
      required this.onSelected,
      this.badgeCounts = const []});
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 每个入口的未读数（按 [routes] 的顺序，缺省为 0）。
  final List<int> badgeCounts;

  /// 角标文字：超过 99 显示 99+。
  static String badgeLabel(int count) => count > 99 ? '99+' : '$count';

  /// 给导航图标加未读角标；没有未读时原样返回。
  static Widget withUnreadBadge(Widget icon, int count) {
    if (count <= 0) return icon;
    return Badge(
      label: Text(badgeLabel(count)),
      backgroundColor: AppColors.error,
      child: icon,
    );
  }

  int _badgeAt(int index) =>
      index < badgeCounts.length ? badgeCounts[index] : 0;

  static const routes = [
    '/home/chats',
    '/home/contacts',
    '/home/workspace',
    '/home/ai/bots',
    '/home/me'
  ];
  static const labels = ['消息', '联系人', '工作区', 'AI 助手', '我'];
  static const symbols = [
    PMSymbol.chat,
    PMSymbol.contacts,
    PMSymbol.workspace,
    PMSymbol.ai,
    PMSymbol.profile
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Material(
        color: AppColors.surface,
        child: DecoratedBox(
          decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.borderLight))),
          child: SafeArea(
              child: Column(children: [
            const SizedBox(height: PMSpacing.xl),
            const Tooltip(message: 'PM chat', child: PMChatMark(size: 40)),
            const SizedBox(height: PMSpacing.xxl),
            Expanded(
                child: SingleChildScrollView(
                    child: Column(children: [
              for (var index = 0; index < labels.length; index++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Semantics(
                    selected: selectedIndex == index,
                    button: true,
                    label: labels[index],
                    excludeSemantics: true,
                    onTap: () => onSelected(index),
                    child: InkWell(
                      onTap: () => onSelected(index),
                      borderRadius: BorderRadius.circular(PMRadius.m),
                      child: AnimatedContainer(
                        duration: PMMotion.duration(context, PMMotion.medium),
                        curve: PMMotion.curveStandard,
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: PMSpacing.m),
                        decoration: BoxDecoration(
                          color: selectedIndex == index
                              ? AppColors.pixelBlue
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(PMRadius.m),
                        ),
                        child: Column(children: [
                          withUnreadBadge(
                              PMSymbolIcon(symbols[index],
                                  size: 23,
                                  color: selectedIndex == index
                                      ? AppColors.primary
                                      : AppColors.textSecondary),
                              _badgeAt(index)),
                          const SizedBox(height: 6),
                          Text(labels[index],
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selectedIndex == index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selectedIndex == index
                                      ? AppColors.primary
                                      : AppColors.textSecondary)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]))),
            IconButton(
                tooltip: '设置',
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
                icon: const PMSymbolIcon(PMSymbol.settings)),
            const SizedBox(height: PMSpacing.l),
          ])),
        ),
      ),
    );
  }
}
