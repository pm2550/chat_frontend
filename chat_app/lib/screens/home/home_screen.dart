import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_brand.dart';
import '../../constants/app_colors.dart';
import '../../design/pm_symbol_icon.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../../services/auth_service.dart';
import '../../services/chat_data_service.dart';
import 'chat_list_page.dart';
import 'contacts_page.dart';
import 'profile_page.dart';
import '../ai/ai_hub_page.dart';
import '../settings/settings_screen.dart';
import '../workspace/workspace_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    @visibleForTesting this.pageBuilder,
  });

  @visibleForTesting
  final Widget Function(BuildContext context, int index, String aiSection)?
      pageBuilder;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _aiSection = 'bots';
  String? _cachedAiSection;
  final AuthService _authService = AuthService();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  late final List<Widget?> _pageCache =
      List<Widget?>.filled(_tabs.length, null);

  @override
  void initState() {
    super.initState();
    unawaited(_warmHomeCaches());
  }

  Future<void> _warmHomeCaches() async {
    try {
      await Future.wait<void>([
        ChatDataService().getChatRooms().then((_) {}),
        ContactsPage.warmDirectoryCache(),
        AiHubPage.warmCache(),
      ]);
    } catch (_) {
      // Cache warming is a latency optimization; visible pages still load normally.
    }
  }

  static const List<_HomeTabSpec> _tabs = [
    _HomeTabSpec(
      route: '/home/chats',
      label: '消息',
      desktopLabel: '消息',
      icon: PMSymbol.chat,
      selectedIcon: PMSymbol.chat,
    ),
    _HomeTabSpec(
      route: '/home/contacts',
      label: '联系人',
      desktopLabel: '联系人',
      icon: PMSymbol.contacts,
      selectedIcon: PMSymbol.contacts,
    ),
    _HomeTabSpec(
      route: '/home/workspace',
      label: '工作区',
      desktopLabel: '工作区',
      icon: PMSymbol.workspace,
      selectedIcon: PMSymbol.workspace,
    ),
    _HomeTabSpec(
      route: '/home/ai/bots',
      label: 'AI',
      desktopLabel: 'AI 助手',
      icon: PMSymbol.ai,
      selectedIcon: PMSymbol.ai,
    ),
    _HomeTabSpec(
      route: '/home/me',
      label: '我',
      desktopLabel: '我',
      icon: PMSymbol.profile,
      selectedIcon: PMSymbol.profile,
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeName =
        ModalRoute.of(context)?.settings.name ?? Uri.base.fragment;
    final parsed = _tabFromRoute(routeName);
    if (parsed.index != _currentIndex || parsed.aiSection != _aiSection) {
      setState(() {
        _currentIndex = parsed.index;
        _aiSection = parsed.aiSection;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            _buildDesktopSidebar(context),
            Expanded(child: _buildBodyWithMigrationBanner()),
          ],
        ),
      );
    }

    if (PMBreakpoints.isTablet(context)) {
      return Scaffold(
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderLight),
                  ),
                  boxShadow: [AppColors.appBarShadow],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_tabs.length, (index) {
                      final tab = _tabs[index];
                      final selected = _currentIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: selected,
                          avatar: PMSymbolIcon(
                            selected ? tab.selectedIcon : tab.icon,
                            size: 18,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          label: Text(tab.desktopLabel),
                          onSelected: (_) => _selectTab(index),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBodyWithMigrationBanner()),
          ],
        ),
      );
    }

    return Scaffold(
      body: _buildBodyWithMigrationBanner(),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          boxShadow: [AppColors.appBarShadow],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          destinations: _tabs
              .map(
                (tab) => NavigationDestination(
                  icon: PMSymbolIcon(tab.icon),
                  selectedIcon: PMSymbolIcon(
                    tab.selectedIcon,
                    color: AppColors.primary,
                  ),
                  label: tab.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCachedTabStack() {
    return PageStorage(
      bucket: _pageStorageBucket,
      child: IndexedStack(
        index: _currentIndex,
        children: List.generate(_tabs.length, (index) {
          final shouldBuild =
              index == _currentIndex || _pageCache[index] != null;
          return TickerMode(
            enabled: index == _currentIndex,
            child: shouldBuild ? _pageAt(index) : const SizedBox.shrink(),
          );
        }),
      ),
    );
  }

  Widget _buildBodyWithMigrationBanner() {
    return ListenableBuilder(
      listenable: _authService,
      builder: (context, _) {
        final showBanner = _authService.passwordUpgradePending;
        if (!showBanner) {
          return _buildCachedTabStack();
        }
        return Column(
          children: [
            SafeArea(
              bottom: false,
              child: MaterialBanner(
                backgroundColor: const Color(0xFFFFFBEB),
                leading: const PMSymbolIcon(
                  PMSymbol.settings,
                  color: Color(0xFFD97706),
                ),
                content: const Text(
                  '为了你的账户安全，请更新一次密码，之后服务器不会再收到明文密码。',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: _openPasswordUpgrade,
                    child: const Text('立即修改'),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildCachedTabStack()),
          ],
        );
      },
    );
  }

  void _openPasswordUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(authService: _authService),
      ),
    );
  }

  Widget _pageAt(int index) {
    if (index == 3 &&
        (_pageCache[index] == null || _cachedAiSection != _aiSection)) {
      _cachedAiSection = _aiSection;
      return _pageCache[index] = _createPage(index);
    }
    return _pageCache[index] ??= _createPage(index);
  }

  Widget _createPage(int index) {
    final customPage = widget.pageBuilder?.call(context, index, _aiSection);
    if (customPage != null) {
      return customPage;
    }

    return switch (index) {
      0 => const ChatListPage(key: PageStorageKey<String>('home-chats')),
      1 => const ContactsPage(key: PageStorageKey<String>('home-contacts')),
      2 => const WorkspacePage(key: PageStorageKey<String>('home-workspace')),
      3 => AiHubPage(
          key: const PageStorageKey<String>('home-ai'),
          initialSection: _aiSection,
        ),
      4 => const ProfilePage(key: PageStorageKey<String>('home-me')),
      _ => const SizedBox.shrink(),
    };
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      if (index == 3 && _aiSection.isEmpty) {
        _aiSection = 'bots';
      }
    });
    _syncRoute(_tabs[index].route);
  }

  void _syncRoute(String route) {
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(route),
      replace: true,
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.borderLight)),
        boxShadow: [AppColors.appBarShadow],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PMChatLogo(size: 44, showWordmark: true),
              const SizedBox(height: 28),
              for (var index = 0; index < _tabs.length; index++)
                _buildDesktopNavItem(index: index, tab: _tabs[index]),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white),
                    SizedBox(height: 10),
                    Text(
                      AppBrand.tagline,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '聊天、文件、Bot 和 Agent 都在一个工作台里。',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Divider(color: AppColors.borderLight),
              const SizedBox(height: 10),
              Text(
                AppBrand.name,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavItem({
    required int index,
    required _HomeTabSpec tab,
  }) {
    final selected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _selectTab(index),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.pixelBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primaryLight : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.cloud,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.primaryLight : AppColors.border,
                  ),
                ),
                child: PMSymbolIcon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tab.desktopLabel,
                  style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _HomeRouteState _tabFromRoute(String routeName) {
    final normalized = routeName.startsWith('/') ? routeName : '/$routeName';
    final uri = Uri.tryParse(normalized);
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.isEmpty || segments.first != 'home') {
      return const _HomeRouteState(0, 'bots');
    }
    if (segments.length == 1) {
      return const _HomeRouteState(0, 'bots');
    }
    return switch (segments[1]) {
      'contacts' => const _HomeRouteState(1, 'bots'),
      'workspace' => const _HomeRouteState(2, 'bots'),
      'ai' => _HomeRouteState(
          3,
          segments.length >= 3 ? segments[2] : 'bots',
        ),
      'me' => const _HomeRouteState(4, 'bots'),
      _ => const _HomeRouteState(0, 'bots'),
    };
  }
}

class _HomeTabSpec {
  const _HomeTabSpec({
    required this.route,
    required this.label,
    required this.desktopLabel,
    required this.icon,
    required this.selectedIcon,
  });

  final String route;
  final String label;
  final String desktopLabel;
  final PMSymbol icon;
  final PMSymbol selectedIcon;
}

class _HomeRouteState {
  const _HomeRouteState(this.index, this.aiSection);

  final int index;
  final String aiSection;
}
