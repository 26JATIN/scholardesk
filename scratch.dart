import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;

void main() {
  final file = File('test.json');
  if (!file.existsSync()) {
    print("test.json not found");
    return;
  }
  
  final jsonStr = file.readAsStringSync();
  final data = json.decode(jsonStr);
  final html = data['content'] as String;
  
  var document = html_parser.parse(html);
  var dayCards = document.querySelectorAll('.timetable-mobile .day-card');
  
  print("Found ${dayCards.length} day cards");
  
  final Map<String, List<Map<String, String>>> timetable = {};
  final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  
  for (var dayCard in dayCards) {
    final dayHeader = dayCard.querySelector('.day-header .fw-bold')?.text.trim() ?? '';
    String dayName = dayHeader.split(' ').first;
    if (!days.contains(dayName)) continue;

    final periods = timetable[dayName] ?? [];

    var periodCards = dayCard.querySelectorAll('.period-card');
    for (var periodCard in periodCards) {
      final detailsDiv = periodCard.querySelector('.period-details');
      if (detailsDiv == null) continue;

      if (detailsDiv.text.contains('-- No Lecture --')) {
        continue;
      }

      final subjectDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Subject:'), orElse: () => document.createElement('div'));
      final locationDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Location:'), orElse: () => document.createElement('div'));
      final groupDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Group:'), orElse: () => document.createElement('div'));
      final teacherDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Teacher:'), orElse: () => document.createElement('div'));

      final subject = subjectDiv.text.replaceAll('Subject:', '').trim();
      final location = locationDiv.text.replaceAll('Location:', '').trim();
      final group = groupDiv.text.replaceAll('Group:', '').trim();
      final teacher = teacherDiv.text.replaceAll('Teacher:', '').trim();

      final timeText = periodCard.querySelector('.small.text-muted')?.text.trim() ?? '';
      final timeRange = timeText.split('|').first.trim();

      if (subject.isNotEmpty) {
        periods.add({
          'time': timeRange,
          'subject': subject,
          'location': location,
          'group': group,
          'teacher': teacher,
        });
      }
    }
    
    timetable[dayName] = periods;
  }
  
  timetable.forEach((day, periods) {
    print("$day: ${periods.length} periods");
    for (var p in periods) {
      print("  - ${p['time']} | ${p['subject']}");
    }
  });
}
