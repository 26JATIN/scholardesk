import 'package:flutter/material.dart';

/// Pre-created TextStyle constants for performance optimization.
/// Using const constructors prevents creating new objects on every build.
class AppTextStyles {
  AppTextStyles._();

  // ============== INTER FONT STYLES ==============

  // Caption / small text
  static const TextStyle caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle captionMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  // Body text
  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodySmallMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  // Label text
  static const TextStyle label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // Heading styles
  static const TextStyle h3 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle h4 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle statValue = TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  // ============== OUTFIT FONT STYLES ==============

  static const TextStyle outfitRegular = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle outfitMedium = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  static const TextStyle outfitSemiBold = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle outfitBold = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  // Outfit heading styles
  static const TextStyle headingLarge = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  // Stat item styles (Outfit)
  static const TextStyle statItemValue = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// Extension to easily copy TextStyles with color
extension TextStyleCopyWithColor on TextStyle {
  TextStyle withAppColor(Color color) => copyWith(color: color);

  TextStyle withGrey([int shade = 400]) {
    switch (shade) {
      case 300:
        return copyWith(color: const Color(0xFF9CA3AF));
      case 400:
        return copyWith(color: const Color(0xFF9CA3AF));
      case 500:
        return copyWith(color: const Color(0xFF6B7280));
      case 600:
        return copyWith(color: const Color(0xFF4B5563));
      default:
        return copyWith(color: const Color(0xFF9CA3AF));
    }
  }
}

/// Pre-created BoxDecoration constants for cards
class AppDecorations {
  AppDecorations._();

  static const BorderRadius cardBorderRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius smallBorderRadius = BorderRadius.all(Radius.circular(10));
  static const BorderRadius mediumBorderRadius = BorderRadius.all(Radius.circular(16));
  static const BorderRadius largeBorderRadius = BorderRadius.all(Radius.circular(24));

  static BoxDecoration card({Color? backgroundColor}) => BoxDecoration(
        color: backgroundColor,
        borderRadius: cardBorderRadius,
      );

  static BoxDecoration cardWithShadow({required bool isDark}) => BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : Colors.white,
        borderRadius: cardBorderRadius,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration chip({required Color backgroundColor}) => BoxDecoration(
        color: backgroundColor,
        borderRadius: smallBorderRadius,
      );

  static BoxDecoration iconContainer({required Color iconBackgroundColor}) => BoxDecoration(
        color: iconBackgroundColor.withOpacity(0.1),
        borderRadius: smallBorderRadius,
      );
}

/// Pre-created EdgeInsets constants
class AppPadding {
  AppPadding._();

  static const EdgeInsets cardPadding = EdgeInsets.all(20);
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  static const EdgeInsets smallPadding = EdgeInsets.all(8);
  static const EdgeInsets mediumPadding = EdgeInsets.all(16);
  static const EdgeInsets iconPadding = EdgeInsets.all(8);
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(vertical: 8);
}