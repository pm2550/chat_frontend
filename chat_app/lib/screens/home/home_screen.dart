import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../design/pm_symbol_icon.dart';
import '../../widgets/pm_navigation_rail.dart';
import '../../widgets/pm_responsive.dart';
import '../../services/auth_service.dart';
import '../../services/background_message_service.dart';
import '../../services/notification_launch.dart';
import 'chat_list_page.dart';
import 'contacts_page.dart';
import 'profile_page.dart';
import '../ai/ai_hub_page.dart';
import '../settings/settings_screen.dart';
import '../workspace/workspace_page.dart';

typedef HomeCacheWarmer = Future<void> Function();

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    @visibleForTesting this.pageBuilder,
    @visibleForTesting this.cacheWarmer,
    this.cacheWarmupDelay = const Duration(milliseconds: 1200),
  });

  @visibleForTesting
  final Widget Function(BuildContext context, int index, String aiSection)?
      pageBuilder;

  @visibleForTesting
  final HomeCacheWarmer? cacheWarmer;
  final Duration cacheWarmupDelay;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _aiSection = 'bots';
  ModalRoute<dynamic>? _homeRoute;
  bool _didReadInitialRoute = false;
  bool _homeRouteWasCurrent = false;
  bool _aiPageVisited = false;
  final AuthService _authService = AuthService();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  late final List<Widget?> _pageCache =
      List<Widget?>.filled(_tabs.length, null);
  Timer? _cacheWarmupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Android：登录后启动后台常驻服务；补上"点通知冷启动"时还没来得及跳的聊天。
      unawaited(BackgroundMessageService.ensureStarted());
      flushPendingNotificationRoute();
      _cacheWarmupTimer = Timer(widget.cacheWarmupDelay, () {
        unawaited((widget.cacheWarmer ?? _warmHiddenHomeCaches)());
      });
    });
  }

  Future<void> _warmHiddenHomeCaches() async {
    await _warmSafely(ContactsPage.warmDirectoryCache);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _warmSafely(AiHubPage.warmCache);
  }

  Future<void> _warmSafely(Future<void> Function() warmer) async {
    try {
      await warmer();
    } catch (_) {
      // Visible pages remain usable when background warming fails.
    }
  }

  @override
  void dispose() {
    _cacheWarmupTimer?.cancel();
    super.dispose();
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
    final route = ModalRoute.of(context);
    final firstRead = !_didReadInitialRoute || !identical(route, _homeRoute);
    if (firstRead) {
      _homeRoute = route;
      _didReadInitialRoute = true;
      final parsed = _tabFromRoute(route?.settings.name ?? Uri.base.fragment);
      _currentIndex = parsed.index;
      _aiSection = parsed.aiSection;
    }
    final isCurrent = route?.isCurrent ?? true;
    final returnedToHome = !firstRead && !_homeRouteWasCurrent && isCurrent;
    _homeRouteWasCurrent = isCurrent;
    if (returnedToHome) {
      // Tab changes update browser history, not this route's original settings.
      // Returning from a child must keep the selected tab and restore its URL.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !(_homeRoute?.isCurrent ?? true)) return;
        _syncRoute(_currentIndex == 3
            ? '/home/ai/$_aiSection'
            : _tabs[_currentIndex].route);
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
          final wasBuilt =
              index == 3 ? _aiPageVisited : _pageCache[index] != null;
          final shouldBuild = index == _currentIndex || wasBuilt;
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
    if (index == 3) {
      _aiPageVisited = true;
      return _createPage(index);
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
          onSectionChanged: _setAiSection,
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
    _syncRoute(index == 3 ? '/home/ai/$_aiSection' : _tabs[index].route);
  }

  void _setAiSection(String section) {
    if (_aiSection == section) return;
    setState(() => _aiSection = section);
    if (_currentIndex == 3) {
      _syncRoute('/home/ai/$section');
    }
  }

  void _syncRoute(String route) {
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(route),
      replace: true,
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) => PMNavigationRail(
        selectedIndex: _currentIndex,
        onSelected: _selectTab,
      );

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
