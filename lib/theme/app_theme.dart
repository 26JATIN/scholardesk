import 'package:flutter/material.dart';

class AppTheme {
  // Professional Blue Color Palette
  static const Color primaryColor = Color.fromARGB(233, 23, 62, 135); // Deep Blue (Professional)
  static const Color secondaryColor = Color(0xFF0369A1); // Ocean Blue
  static const Color tertiaryColor = Color(0xFF475569); // Slate Gray
  static const Color accentColor = Color(0xFF0284C7); // Sky Blue
  static const Color successColor = Color(0xFF059669); // Emerald
  static const Color warningColor = Color(0xFFD97706); // Amber (muted)
  static const Color errorColor = Color(0xFFDC2626); // Red
  static const Color surfaceColor = Color(0xFFF8FAFC); // Cool Gray
  static const Color cardColor = Colors.white;

  // Dark theme colors - Pitch Black AMOLED
  static const Color darkSurfaceColor = Color(0xFF000000);
  static const Color darkCardColor = Color(0xFF0D0D0D);
  static const Color darkElevatedColor = Color(0xFF1A1A1A);

  // Smooth animation durations
  static const Duration fastAnimation = Duration(milliseconds: 100);
  static const Duration normalAnimation = Duration(milliseconds: 150);
  static const Duration slowAnimation = Duration(milliseconds: 200);

  // Smooth curves
  static const Curve smoothCurve = Curves.easeOutCubic;
  static const Curve bouncyCurve = Curves.easeOutBack;

  // Gradient combinations (kept for legacy support but not used in new design)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E40AF), Color(0xFF0284C7)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
  );

  static const LinearGradient warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD97706), Color(0xFFDC2626)],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF0284C7)],
  );

  // Pre-built TextStyles for button theming (light)
  static const TextStyle lightButtonText = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  // Pre-built TextStyles for button theming (dark)
  static const TextStyle darkButtonText = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  // Pre-built AppBar title styles
  static const TextStyle lightAppBarTitle = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  static const TextStyle darkAppBarTitle = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  // Navigation label styles
  static const TextStyle navLabelSelected = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle navLabelUnselectedLight = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  ThemeData get lightTheme => _buildLightTheme();
  ThemeData get darkTheme => _buildDarkTheme();

  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: tertiaryColor,
        surface: surfaceColor,
        error: errorColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: surfaceColor,
      textTheme: _buildTextTheme(Brightness.light),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        color: cardColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: lightButtonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: lightButtonText,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
        titleTextStyle: lightAppBarTitle,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 70,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withOpacity(0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor, size: 26);
          }
          return IconThemeData(color: Colors.grey.shade500, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return navLabelSelected.copyWith(color: primaryColor);
          }
          return navLabelUnselectedLight.copyWith(color: Colors.grey.shade500);
        }),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: tertiaryColor,
        surface: darkSurfaceColor,
        error: errorColor,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkSurfaceColor,
      textTheme: _buildTextTheme(Brightness.dark),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        color: darkCardColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: darkButtonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: darkButtonText,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: darkSurfaceColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        titleTextStyle: darkAppBarTitle,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 70,
        backgroundColor: darkCardColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withOpacity(0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryColor, size: 26);
          }
          return IconThemeData(color: Colors.grey.shade600, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return navLabelSelected.copyWith(color: primaryColor);
          }
          return navLabelUnselectedLight.copyWith(color: Colors.grey.shade600);
        }),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.1),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final Color textColor = brightness == Brightness.light
        ? Colors.black87
        : Colors.white;

    return TextTheme(
      displayLarge: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 57,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.25,
      ).copyWith(color: textColor),
      displayMedium: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 45,
        fontWeight: FontWeight.bold,
      ).copyWith(color: textColor),
      displaySmall: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 36,
        fontWeight: FontWeight.bold,
      ).copyWith(color: textColor),
      headlineLarge: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ).copyWith(color: textColor),
      headlineMedium: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ).copyWith(color: textColor),
      headlineSmall: const TextStyle(
        fontFamily: 'Outfit',
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ).copyWith(color: textColor),
      titleLarge: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ).copyWith(color: textColor),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ).copyWith(color: textColor),
      titleSmall: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ).copyWith(color: textColor),
      bodyLarge: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.normal,
      ).copyWith(color: textColor),
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.normal,
      ).copyWith(color: textColor),
      bodySmall: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.normal,
      ).copyWith(color: textColor),
      labelLarge: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ).copyWith(color: textColor),
    );
  }
}