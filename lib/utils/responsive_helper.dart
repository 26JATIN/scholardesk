import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
/// Responsive helper class for adaptive layouts across web and mobile
class ResponsiveHelper {
  final BuildContext context;
  
  ResponsiveHelper(this.context);
  
  /// Screen width
  double get screenWidth => MediaQuery.of(context).size.width;
  
  /// Screen height
  double get screenHeight => MediaQuery.of(context).size.height;
  
  /// Safe area padding
  EdgeInsets get safeArea => MediaQuery.of(context).padding;
  
  // ============ BREAKPOINTS ============
  
  /// Mobile: < 600px
  bool get isMobile => screenWidth < 600;
  
  /// Tablet: 600-1024px
  bool get isTablet => screenWidth >= 600 && screenWidth < 1024;
  
  /// Desktop: >= 1024px
  bool get isDesktop => screenWidth >= 1024;
  
  /// Large desktop: >= 1440px
  bool get isLargeDesktop => screenWidth >= 1440;
  
  /// Is running in web browser
  static bool get isWebBrowser => kIsWeb;
  
  /// Is iOS platform (native or web)
  static bool get isIOSPlatform {
    if (kIsWeb) {
      // Check user agent for iOS Safari
      return false; // Will be detected via CSS in web
    }
    try {
      return Platform.isIOS;
    } catch (e) {
      return false;
    }
  }
  
  // ============ RESPONSIVE SIZING ============
  
  /// Maximum content width for large screens (centered layout)
  double get maxContentWidth {
    if (isLargeDesktop) return 900;
    if (isDesktop) return 800;
    if (isTablet) return 700;
    return screenWidth; // Full width on mobile
  }
  
  /// Scale factor based on screen width
  double get scaleFactor {
    if (isLargeDesktop) return 1.15;
    if (isDesktop) return 1.1;
    if (isTablet) return 1.05;
    return 1.0;
  }
  
  /// Responsive font size
  double responsiveFontSize(double baseSize) {
    return baseSize * scaleFactor;
  }
  
  /// Responsive padding value
  double responsivePadding(double basePadding) {
    if (isLargeDesktop) return basePadding * 1.5;
    if (isDesktop) return basePadding * 1.3;
    if (isTablet) return basePadding * 1.15;
    return basePadding;
  }
  
  /// Responsive horizontal padding for screen edges
  double get horizontalPadding {
    if (isLargeDesktop) return 32;
    if (isDesktop) return 24;
    if (isTablet) return 20;
    return 16;
  }
  
  /// Responsive vertical spacing
  double get verticalSpacing {
    if (isDesktop) return 24;
    if (isTablet) return 20;
    return 16;
  }
  
  /// Responsive card padding
  double get cardPadding {
    if (isDesktop) return 24;
    if (isTablet) return 20;
    return 16;
  }
  
  /// Number of grid columns for adaptive layouts
  int get gridColumns {
    if (isLargeDesktop) return 4;
    if (isDesktop) return 3;
    if (isTablet) return 3;
    return 2;
  }
  
  /// Responsive icon size
  double responsiveIconSize(double baseSize) {
    if (isDesktop) return baseSize * 1.2;
    if (isTablet) return baseSize * 1.1;
    return baseSize;
  }
  
  /// Responsive border radius
  double responsiveBorderRadius(double baseRadius) {
    if (isDesktop) return baseRadius * 1.2;
    return baseRadius;
  }
  
  // ============ LAYOUT HELPERS ============
  
  /// Wrap content with max width constraint for large screens
  Widget constrainedContent({required Widget child, double? maxWidth}) {
    final width = maxWidth ?? maxContentWidth;
    
    if (screenWidth <= width) {
      return child;
    }
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    );
  }
  
  /// Responsive edge padding
  EdgeInsets get screenPadding => EdgeInsets.symmetric(
    horizontal: horizontalPadding,
    vertical: verticalSpacing,
  );
  
  /// Get appropriate aspect ratio for cards based on screen size
  double get cardAspectRatio {
    if (isDesktop) return 1.4;
    if (isTablet) return 1.3;
    return 1.2;
  }
}
/// Extension for easy access to ResponsiveHelper
extension ResponsiveContext on BuildContext {
  ResponsiveHelper get responsive => ResponsiveHelper(this);
  
  bool get isMobile => responsive.isMobile;
  bool get isTablet => responsive.isTablet;
  bool get isDesktop => responsive.isDesktop;
  double get maxContentWidth => responsive.maxContentWidth;
}