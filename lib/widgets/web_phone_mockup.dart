import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A wrapper widget that displays the app inside a phone mockup frame on web.
/// On mobile platforms, it just returns the child directly.
class WebPhoneMockup extends StatelessWidget {
  final Widget child;
  
  const WebPhoneMockup({super.key, required this.child});
  
  @override
  Widget build(BuildContext context) {
    // On mobile, just return the child directly
    if (!kIsWeb) {
      return child;
    }
    
    final screenSize = MediaQuery.of(context).size;
    
    // Phone mockup dimensions (iPhone 14 Pro aspect ratio)
    const double phoneWidth = 390;
    const double phoneHeight = 844;
    const double borderRadius = 50;
    const double bezelWidth = 12;
    
    // Calculate scale to fit on screen with padding
    final availableHeight = screenSize.height - 40; // 20px padding top/bottom
    final availableWidth = screenSize.width - 40;
    
    double scale = 1.0;
    if (availableHeight < phoneHeight + bezelWidth * 2) {
      scale = availableHeight / (phoneHeight + bezelWidth * 2);
    }
    if (availableWidth < phoneWidth + bezelWidth * 2) {
      final widthScale = availableWidth / (phoneWidth + bezelWidth * 2);
      scale = scale < widthScale ? scale : widthScale;
    }
    
    // Clamp scale
    scale = scale.clamp(0.5, 1.0);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600, // Limit width to be comfortable (like a wide phone/small tablet)
          ),
          child: Container(
            // Add a subtle shadow to separate app from black background
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ClipRect(
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
