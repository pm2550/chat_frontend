import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../widgets/pm_brand.dart';
import '../widgets/update_dialog.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
      ),
    );

    _startAnimation();
  }

  void _startAnimation() async {
    await _animationController.forward();

    // Check for updates before navigating (pre-login, no auth required).
    // Failures are silently swallowed — never block startup.
    try {
      final check = await UpdateService.checkForUpdate();
      if (mounted && check.updateAvailable) {
        await UpdateDialog.show(context, check);
        // If force update, the dialog is not dismissible — user must
        // tap "update" which opens the browser. The app stays on splash.
        if (check.forceUpdate) return;
      }
    } catch (_) {
      // ignore
    }

    final route = await _resolveInitialRoute();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed(route);
    }
  }

  Future<String> _resolveInitialRoute() async {
    final requestedRoute = _requestedColdStartRoute();
    if (requestedRoute == '/register') {
      return '/register';
    }

    final authenticated = await AuthService().ensureAuthenticated();
    if (!authenticated) {
      return '/login';
    }

    return requestedRoute ?? '/home';
  }

  String? _requestedColdStartRoute() {
    final fragment = Uri.base.fragment;
    if (fragment.isEmpty || fragment == '/') {
      return null;
    }

    final route = fragment.split('?').first;
    const allowedColdStartRoutes = {
      '/home',
      '/settings',
      '/register',
    };
    return allowedColdStartRoutes.contains(route) ? route : null;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PMChatPattern(
        dark: true,
        dense: true,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 132,
                        height: 132,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.20),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: const PMChatMark(size: 92),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              AnimatedBuilder(
                animation: _fadeAnimation,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Column(
                      children: [
                        PMChatLogo(
                          size: 0,
                          showWordmark: true,
                          bright: true,
                          centered: true,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 60),
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
