import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Палитра DiaryAI: глубокий тёмно-синий фон с тёплыми акцентами лаванды и янтаря.
/// Атмосфера интимная, спокойная, дорогая.

class AppColors {
  // Бренд-акценты
  static const lavender = Color(0xFFB8A4E3);   // основной акцент (фиолетовый дым)
  static const amber = Color(0xFFE8B86C);      // тёплый янтарь (категории, выделения)
  static const coral = Color(0xFFE38C7A);      // мягкий коралл (для предупреждений / ИИ)

  // Светлая тема
  static const lightBg = Color(0xFFF7F4EE);    // тёплый кремовый
  static const lightSurface = Color(0xFFFFFEFA);
  static const lightInk = Color(0xFF2D2A3E);   // насыщенный сине-серый

  // Тёмная тема
  static const darkBg = Color(0xFF1A1825);     // глубокий почти-чёрный с фиолетовым подтоном
  static const darkSurface = Color(0xFF24213A);
  static const darkSurfaceHigh = Color(0xFF2E2B45);
  static const darkInk = Color(0xFFEFEAE3);
  static const darkInkSoft = Color(0xFFB5AECC);
}

/// Градиенты, которые используются в фоне, кнопках, картинках.
class AppGradients {
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB8A4E3), Color(0xFF8770C7)],
  );

  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8B86C), Color(0xFFE38C7A)],
  );

  static const darkBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1825), Color(0xFF252140), Color(0xFF1A1825)],
    stops: [0, 0.5, 1],
  );

  static const lightBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7F4EE), Color(0xFFFFFEFA), Color(0xFFF2EDE0)],
    stops: [0, 0.5, 1],
  );

  static const aiCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x33B8A4E3), Color(0x22E8B86C)],
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.lavender,
    brightness: Brightness.light,
    surface: AppColors.lightSurface,
    primary: const Color(0xFF7A5FBC),
    secondary: AppColors.amber,
  ).copyWith(
    surfaceContainer: const Color(0xFFFBF7EF),
    surfaceContainerHigh: const Color(0xFFF2ECDC),
    onSurface: AppColors.lightInk,
  );
  return _base(scheme, brightness: Brightness.light);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.lavender,
    brightness: Brightness.dark,
    surface: AppColors.darkBg,
    primary: AppColors.lavender,
    secondary: AppColors.amber,
  ).copyWith(
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkSurfaceHigh,
    onSurface: AppColors.darkInk,
    onSurfaceVariant: AppColors.darkInkSoft,
  );
  return _base(scheme, brightness: Brightness.dark);
}

ThemeData _base(ColorScheme scheme, {required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final textTheme = GoogleFonts.manropeTextTheme(
    (isDark ? ThemeData.dark() : ThemeData.light()).textTheme,
  ).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme.copyWith(
      displaySmall: GoogleFonts.fraunces(
        textStyle: textTheme.displaySmall,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: scheme.onSurface,
      ),
      headlineMedium: GoogleFonts.fraunces(
        textStyle: textTheme.headlineMedium,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      headlineSmall: GoogleFonts.fraunces(
        textStyle: textTheme.headlineSmall,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleLarge: GoogleFonts.fraunces(
        textStyle: textTheme.titleLarge,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? AppColors.darkSurfaceHigh.withValues(alpha: 0.6)
          : Colors.white.withValues(alpha: 0.7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w500),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.3),
      thickness: 1,
    ),
  );
}
