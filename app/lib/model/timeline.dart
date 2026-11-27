import '../core/ids.dart';
import 'models.dart';

const timelineEventsKey = 'events';
const timelineDefaultSize = (width: 720.0, height: 280.0);

class TimelineEvent {
  TimelineEvent({
    String? id,
    required this.title,
    required this.day,
    this.canvasPageId,
  }) : id = id ?? newId();

  final String id;
  final String title;
  final DateTime day;
  final String? canvasPageId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'day': day.toIso8601String(),
    if (canvasPageId != null) 'canvasPageId': canvasPageId,
  };

  static TimelineEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], date = raw['day'];
    final day = date is String ? DateTime.tryParse(date) : null;
    if (id is! String || id.isEmpty || title is! String || day == null) return null;
    return TimelineEvent(
      id: id, title: title, day: day,
      canvasPageId: raw['canvasPageId'] is String ? raw['canvasPageId'] as String : null,
    );
  }

  static List<TimelineEvent> of(Block block) {
    final raw = block.content[timelineEventsKey];
    if (raw is! List) return [];
    return raw.map(fromJson).whereType<TimelineEvent>().toList()
      ..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        return byDay == 0 ? a.id.compareTo(b.id) : byDay;
      });
  }
}

String timelineSummary(Block block) => [
  'Timeline',
  for (final event in TimelineEvent.of(block))
    '${event.day.toIso8601String().split("T").first} — ${event.title}',
].join('\n');
