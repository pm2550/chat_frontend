import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'tokens.dart';

/// One surface, type and control language for all PM Chat screens.
class PMTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        brightness: Brightness.light,
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PMRadius.s),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(PMRadius.s),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      dividerTheme: const DividerThemeData(
          color: AppColors.borderLight, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: PMSpacing.l,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: shape,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(
            horizontal: PMSpacing.xl, vertical: PMSpacing.m),
      )),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: shape,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(
            horizontal: PMSpacing.l, vertical: PMSpacing.m),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: shape,
        minimumSize: const Size(44, 44),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cloud,
        hintStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.borderLight),
        focusedBorder: inputBorder(AppColors.primary, 1.5),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: PMSpacing.l, vertical: PMSpacing.m),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PMRadius.m),
            side: const BorderSide(color: AppColors.borderLight)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.cloud,
        selectedColor: AppColors.pixelBlue,
        side: const BorderSide(color: AppColors.borderLight),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PMRadius.pill)),
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.pixelBlue,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.textSecondary,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(PMRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PMRadius.l)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PMRadius.m)),
      ),
      tooltipTheme:
          const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    );
  }
}
