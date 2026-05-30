import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/downloads/downloads_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'constants/app_brand.dart';
import 'constants/app_colors.dart';
import 'widgets/app_update_listener.dart';
import 'widgets/auth_guard.dart';

void main() {
  runApp(
    const ProviderScope(
      child: ChatApp(),
    ),
  );
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      locale: const Locale('en', 'US'),
      supportedLocales: const [
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.borderLight),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: AppColors.pixelBlue,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimary),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
      ),
      initialRoute: '/',
      builder: (context, child) => AppUpdateListener(
        child: child ?? const SizedBox.shrink(),
      ),
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/downloads': (context) => const DownloadsScreen(),
        '/home': (context) => const AuthGuard(child: HomeScreen()),
        '/chat': (context) => const AuthGuard(child: ChatScreen()),
        '/settings': (context) => const AuthGuard(child: SettingsScreen()),
      },
      onGenerateRoute: (settings) {
        final routeName = settings.name ?? '';
        if (_isHomeRoute(routeName)) {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const AuthGuard(child: HomeScreen()),
          );
        }
        if (_isChatRoute(routeName)) {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const AuthGuard(child: ChatScreen()),
          );
        }
        return null;
      },
    );
  }
}

bool _isHomeRoute(String routeName) {
  final uri = Uri.tryParse(routeName);
  if (uri == null || uri.pathSegments.isEmpty) {
    return false;
  }
  return uri.pathSegments.first == 'home';
}

bool _isChatRoute(String routeName) {
  final uri = Uri.tryParse(routeName);
  if (uri == null || uri.pathSegments.isEmpty) {
    return false;
  }
  return uri.pathSegments.first == 'chat';
}
