import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

/// Parse timetable HTML in background isolate
/// Returns Map with 'timetable' key containing Map<String, List<Map<String, String>>>
Map<String, dynamic> parseTimetableHtmlIsolate(String html) {
  try {
    String htmlToParse = html;

    // Extract content if JSON-wrapped
    try {
      if (html.trim().startsWith('{')) {
        final Map<String, dynamic> decoded =
            Map<String, dynamic>.from(_parseJsonSimple(html));
        if (decoded.containsKey('content')) {
          htmlToParse = decoded['content'].toString();
        }
      }
    } catch (_) {}

    final document = html_parser.parse(htmlToParse);
    final mobileContainers = document.querySelectorAll('.timetable-mobile');

    if (mobileContainers.isEmpty) {
      return {'timetable': <String, List>{}, 'error': null};
    }

    // Use the second container if available (matches timetable screen)
    final targetContainer =
        mobileContainers.length > 1 ? mobileContainers[1] : mobileContainers[0];

    final dayCards = targetContainer.querySelectorAll('.day-card');
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    final timetable = <String, List<Map<String, String>>>{};

    for (var dayCard in dayCards) {
      final dayHeader = dayCard.querySelector('.day-header .fw-bold')?.text.trim() ?? '';
      String dayName = dayHeader.split(' ').first;
      if (!days.contains(dayName)) continue;

      final periods = <Map<String, String>>[];
      final periodCards = dayCard.querySelectorAll('.period-card');

      for (var periodCard in periodCards) {
        final timeText = periodCard.querySelector('.small.text-muted')?.text.trim() ?? '';
        final timeRange = timeText.split('|').first.trim();

        final detailsDiv = periodCard.querySelector('.period-details');
        if (detailsDiv != null) {
          if (detailsDiv.text.contains('-- No Lecture --')) continue;

          String subject = '';
          String location = '';
          String teacher = '';
          String group = '';

          for (var div in detailsDiv.children) {
            final text = div.text;
            if (text.contains('Subject:')) {
              subject = text.replaceAll('Subject:', '').trim();
            } else if (text.contains('Location:')) {
              location = text.replaceAll('Location:', '').trim();
            } else if (text.contains('Teacher:')) {
              teacher = text.replaceAll('Teacher:', '').trim();
            } else if (text.contains('Group:')) {
              group = text.replaceAll('Group:', '').trim();
            }
          }

          if (subject.isNotEmpty) {
            periods.add({
              'time': timeRange,
              'subject': subject,
              'location': location,
              'teacher': teacher,
              'group': group,
            });
          }
        }
      }
      timetable[dayName] = periods;
    }

    return {'timetable': timetable, 'error': null};
  } catch (e) {
    return {'timetable': <String, List>{}, 'error': e.toString()};
  }
}

/// Simple JSON parser for isolate (avoid importing dart:convert issues)
Map<String, dynamic> _parseJsonSimple(String jsonStr) {
  // Simple JSON parsing for the content extraction
  // Handle: {"content": "..."}
  final contentMatch = RegExp(r'"content"\s*:\s*"([^"]*)"').firstMatch(jsonStr);
  if (contentMatch != null) {
    return {'content': contentMatch.group(1)};
  }
  return {};
}

/// Parse attendance HTML in background isolate
/// Returns Map with 'subjects' key containing List of subject data
Map<String, dynamic> parseAttendanceHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    final subjectBoxes = document.querySelectorAll('.tt-box-new');

    final subjects = <Map<String, dynamic>>[];

    for (var box in subjectBoxes) {
      final subject = <String, dynamic>{};

      // Subject Name and Code
      final periodNumberDiv = box.querySelector('.tt-period-number');
      if (periodNumberDiv != null) {
        final spans = periodNumberDiv.querySelectorAll('span');
        if (spans.isNotEmpty) subject['name'] = spans[0].text.trim();
        if (spans.length > 1) subject['code'] = spans[1].text.trim();
      }

      // Details
      final detailsDivs = box.querySelectorAll('.tt-period-name');
      for (var div in detailsDivs) {
        String text = div.text.trim();
        // Normalize whitespace and special chars
        text = text.replaceAll(RegExp(r'[ \s]+'), ' ').trim();

        if (text.toLowerCase().contains('teacher')) {
          final teacherMatch =
              RegExp(r'Teacher\s*:?\s*(.+)', caseSensitive: false).firstMatch(text);
          if (teacherMatch != null) {
            subject['teacher'] = teacherMatch.group(1)?.trim();
          }
        } else if (text.toLowerCase().contains('from') && text.toLowerCase().contains('to')) {
          // Parse date range
          String normalizedText = text.replaceAll(RegExp(r'\s+'), ' ');
          final datePattern = RegExp(
            r'From\s*:?\s*(\d{1,2}\s+\w+\s+\d{4})\s*(?:TO|To|to)\s*:?\s*(\d{1,2}\s+\w+\s+\d{4})',
            caseSensitive: false,
          );
          final match = datePattern.firstMatch(normalizedText);
          if (match != null) {
            subject['fromDate'] = match.group(1)?.trim();
            subject['toDate'] = match.group(2)?.trim();
            subject['duration'] = '${subject['fromDate']} - ${subject['toDate']}';
          }
        } else if (text.toLowerCase().contains('delivered')) {
          final match =
              RegExp(r'Delivered\s*:?\s*(\d+)', caseSensitive: false).firstMatch(text);
          subject['delivered'] = match?.group(1)?.trim() ?? '';
        } else if (text.toLowerCase().contains('attended') &&
            !text.toLowerCase().contains('percentage')) {
          final match =
              RegExp(r'Attended\s*:?\s*(\d+)', caseSensitive: false).firstMatch(text);
          subject['attended'] = match?.group(1)?.trim() ?? '';
        } else if (text.toLowerCase().contains('absent')) {
          final match =
              RegExp(r'Absent\s*:?\s*(\d+)', caseSensitive: false).firstMatch(text);
          subject['absent'] = match?.group(1)?.trim() ?? '';
        } else if (text.toLowerCase().contains('total percentage') ||
            text.toLowerCase().contains('percentage')) {
          final match = RegExp(r'(\d+\.?\d*)\s*%?', caseSensitive: false).firstMatch(text);
          subject['percentage'] = match?.group(1)?.trim();
        }
      }

      if (subject.isNotEmpty) subjects.add(subject);
    }

    return {'subjects': subjects, 'error': null};
  } catch (e) {
    return {'subjects': <Map<String, dynamic>>[], 'error': e.toString()};
  }
}

/// Parse fee receipts HTML in background isolate
Map<String, dynamic> parseFeeReceiptsHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    final receiptContainers = document.querySelectorAll('.receipt-item, .fee-receipt, tr');

    final receipts = <Map<String, String>>[];

    for (var container in receiptContainers) {
      // Try to extract receipt data
      final cells = container.querySelectorAll('td');
      if (cells.length >= 3) {
        receipts.add({
          'receiptNo': cells.length > 0 ? cells[0].text.trim() : '',
          'date': cells.length > 1 ? cells[1].text.trim() : '',
          'amount': cells.length > 2 ? cells[2].text.trim() : '',
        });
      }
    }

    return {'receipts': receipts, 'error': null};
  } catch (e) {
    return {'receipts': <Map<String, String>>[], 'error': e.toString()};
  }
}

/// Generic HTML parsing for any content
Map<String, dynamic> parseGenericHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    return {
      'title': document.querySelector('title')?.text.trim() ?? '',
      'bodyText': document.body?.text.trim() ?? '',
      'error': null,
    };
  } catch (e) {
    return {'title': '', 'bodyText': '', 'error': e.toString()};
  }
}