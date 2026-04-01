import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Conditional import for web-specific back button handling
import 'web_back_stub.dart'
    if (dart.library.html) 'web_back_handler_web.dart';

/// Mixin for screens that need web-friendly back button handling.
/// On web, this prevents the browser from navigating away when pressing back
/// while a dialog/bottom sheet is open.
/// 
/// Usage: Instead of calling showModalBottomSheet/showDialog directly,
/// use the helper methods from this mixin.
mixin WebBackButtonHandler<T extends StatefulWidget> on State<T> {
  
  /// Show a modal bottom sheet that properly handles web back button.
  /// On web, closing via browser back will pop the sheet instead of leaving the site.
  Future<R?> showWebSafeBottomSheet<R>({
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    Color? backgroundColor,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useRootNavigator = true,
  }) {
    return showModalBottomSheet<R>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useRootNavigator: useRootNavigator,
      builder: builder,
    );
  }
  
  /// Show a dialog that properly handles web back button.
  Future<R?> showWebSafeDialog<R>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    bool useRootNavigator = true,
  }) {
    return showDialog<R>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      useRootNavigator: useRootNavigator,
      builder: builder,
    );
  }
}

/// Prevents browser back button from navigating away on web.
/// Call this in main() before runApp().
void setupWebBackButtonHandler() {
  if (kIsWeb) {
    setupWebBackButton();
  }
}
