import 'package:flutter/material.dart';

/// Central theme definition for the app. Screens are not yet wired to
/// consume this — see [AppSpacing] and [AppTextStyles] for the values
/// future slices should migrate ad-hoc styling to.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        iconColor: colorScheme.primary,
      ),
    );
  }
}

/// Reusable spacing scale (in logical pixels) for margins, padding, and gaps.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Semantic colors for the 3-state section-completion indicators (Site Hub
/// and similar progress lists). "Muted" for the empty state comes from the
/// theme's [ColorScheme.outline] instead, since it already tracks light/dark.
class AppStatusColors {
  AppStatusColors._();

  static const Color partial = Color(0xFFFFA000);
  static const Color complete = Color(0xFF2E7D32);
}

/// Named text styles for reuse across screens.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
}
