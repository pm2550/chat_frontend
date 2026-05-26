import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/auth_service.dart';
import 'pm_brand.dart';

class AuthGuard extends StatefulWidget {
  const AuthGuard({
    super.key,
    required this.child,
    this.authService,
  });

  final Widget child;
  final AuthService? authService;

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  late final AuthService _authService;
  late final Future<bool> _authFuture;
  bool _sessionWasValid = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _authService.addListener(_handleAuthChanged);
    _authFuture = _authService.ensureAuthenticated();
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (!_sessionWasValid || _authService.isAuthenticated || !mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authFuture,
      builder: (context, snapshot) {
        final isReady = snapshot.connectionState == ConnectionState.done;
        final isAuthenticated = snapshot.data == true;

        if (isReady && !isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/login',
              (route) => false,
            );
          });
        }

        if (isReady && isAuthenticated) {
          _sessionWasValid = true;
          return widget.child;
        }

        return const Scaffold(
          backgroundColor: AppColors.background,
          body: PMChatPattern(
            dense: true,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}
