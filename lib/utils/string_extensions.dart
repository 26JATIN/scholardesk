import 'package:intl/intl.dart';

extension StringExtension on String {
  String get decodeHtml {
    return this
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

}


String formatTime(String timeStr) {
  try {
    if (timeStr.isEmpty) return '';
    // Try parsing as HH:mm:ss first as that's our expected input
    try {
      final dt = DateFormat('HH:mm:ss').parse(timeStr);
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      // Fallback to standard DateTime parse (ISO etc)
      final dt = DateTime.parse(timeStr);
      return DateFormat('h:mm a').format(dt);
    }
  } catch (e) {
    return '';
  }
}
