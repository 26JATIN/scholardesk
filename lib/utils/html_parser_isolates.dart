import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

/// Background isolate functions for HTML parsing
/// Use compute() to run these off the main thread

/// Parse attendance HTML (extract timetable and subjects)
/// Call with: compute(parseAttendanceHtmlIsolate, htmlString)
Map<String, dynamic> parseAttendanceHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    final timetable = <Map<String, String>>[];
    final subjects = <Map<String, String>>[];

    // Parse timetable - day containers
    final dayContainers = document.querySelectorAll('.tt-day-container');
    for (var dayEl in dayContainers) {
      final dayName = dayEl.querySelector('.day-name, .tt-day-name')?.text.trim() ?? '';
      final periods = dayEl.querySelectorAll('.period-item, .tt-period');

      for (var period in periods) {
        timetable.add({
          'day': dayName,
          'time': period.querySelector('.time, .tt-time')?.text.trim() ?? '',
          'subject': period.querySelector('.subject, .tt-subject')?.text.trim() ?? '',
          'location': period.querySelector('.location, .tt-location')?.text.trim() ?? '',
          'teacher': period.querySelector('.teacher, .tt-teacher')?.text.trim() ?? '',
          'group': period.querySelector('.group, .tt-group')?.text.trim() ?? '',
        });
      }
    }

    // Parse subjects (attendance boxes)
    final subjectBoxes = document.querySelectorAll('.tt-box-new');
    for (var box in subjectBoxes) {
      final periodNumber = box.querySelector('.tt-period-number');
      if (periodNumber != null) {
        final spans = periodNumber.querySelectorAll('span');
        subjects.add({
          'name': spans.isNotEmpty ? spans[0].text.trim() : '',
          'code': spans.length > 1 ? spans[1].text.trim() : '',
        });
      }
    }

    return {
      'timetable': timetable,
      'subjects': subjects,
      'error': null,
    };
  } catch (e) {
    return {
      'timetable': <Map<String, String>>[],
      'subjects': <Map<String, String>>[],
      'error': e.toString(),
    };
  }
}

/// Parse subjects HTML
/// Call with: compute(parseSubjectsHtmlIsolate, htmlString)
Map<String, dynamic> parseSubjectsHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    final subjects = <Map<String, String>>[];
    final semesterTitle = document.querySelector('.semester-title, h2')?.text.trim() ?? '';

    final subjectRows = document.querySelectorAll('.subject-row, tr.subject');
    for (var row in subjectRows) {
      final cells = row.querySelectorAll('td');
      if (cells.length >= 4) {
        subjects.add({
          'name': cells[0].text.trim(),
          'code': cells[1].text.trim(),
          'type': cells[2].text.trim(),
          'credits': cells[3].text.trim(),
        });
      }
    }

    return {
      'subjects': subjects,
      'semesterTitle': semesterTitle,
      'error': null,
    };
  } catch (e) {
    return {
      'subjects': <Map<String, String>>[],
      'semesterTitle': '',
      'error': e.toString(),
    };
  }
}

/// Parse fee receipts HTML
/// Call with: compute(parseFeeReceiptsHtmlIsolate, htmlString)
Map<String, dynamic> parseFeeReceiptsHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    final receipts = <Map<String, String>>[];

    final receiptCards = document.querySelectorAll('.receipt-card, .fee-item');
    for (var card in receiptCards) {
      receipts.add({
        'receiptNo': card.querySelector('.receipt-no')?.text.trim() ?? '',
        'date': card.querySelector('.date, .receipt-date')?.text.trim() ?? '',
        'amount': card.querySelector('.amount')?.text.trim() ?? '',
        'status': card.querySelector('.status')?.text.trim() ?? '',
      });
    }

    return {
      'receipts': receipts,
      'error': null,
    };
  } catch (e) {
    return {
      'receipts': <Map<String, String>>[],
      'error': e.toString(),
    };
  }
}

/// Parse generic HTML to get body text
/// Call with: compute(parseGenericHtmlIsolate, htmlString)
Map<String, dynamic> parseGenericHtmlIsolate(String html) {
  try {
    final document = html_parser.parse(html);
    return {
      'title': document.querySelector('title')?.text.trim() ?? '',
      'bodyText': document.body?.text.trim() ?? '',
      'error': null,
    };
  } catch (e) {
    return {
      'title': '',
      'bodyText': '',
      'error': e.toString(),
    };
  }
}

/// Helper to run HTML parsing in background
/// Usage:
/// ```dart
/// final result = await compute(parseAttendanceHtmlIsolate, htmlString);
/// if (result['error'] == null) {
///   final timetable = result['timetable'] as List<Map<String, String>>;
///   final subjects = result['subjects'] as List<Map<String, String>>;
/// }
/// ```
Future<Map<String, dynamic>> parseInBackground(
  String html,
  Map<String, dynamic> Function(String) isolateFn,
) async {
  return compute(isolateFn, html);
}