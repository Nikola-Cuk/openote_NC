import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/timeline.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('timeline events are ordered and each canvas link persists', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final dir = Directory.systemTemp.createTempSync('onote_timeline_');
    final repo = await Repository.openAt(dir);
    final notebook = await repo.createNotebook('Timeline');
    AppState.syncLogEnabled = false;
    final app = AppState(repo);
    try {
      await app.selectNotebook(notebook.id);
      final timelinePage = app.pageId!;
      app.addTimeline(const Offset(100, 200));
      final block = app.blocks.single;
      final first = TimelineEvent(title: 'Kickoff', day: DateTime(2027, 1, 9));
      final last = TimelineEvent(title: 'Delivery', day: DateTime(2027, 3, 11));
      app.saveTimelineEvent(block, last);
      app.saveTimelineEvent(block, first);
      expect(TimelineEvent.of(block).map((e) => e.title), ['Kickoff', 'Delivery']);

      await app.openTimelineCanvas(block, first);
      final canvas = app.pageId!;
      expect(canvas, isNot(timelinePage));
      expect(app.node(canvas)!.level, 1);
      app.addBlock(Block(
        type: BlockType.text, x: 44, y: 120, content: {'text': 'Event notes'},
      ));
      await app.selectPage(timelinePage);
      final reopened = app.blocks.single;
      expect(TimelineEvent.of(reopened).first.canvasPageId, canvas);
      await app.openTimelineCanvas(reopened, first);
      expect(app.pageId, canvas);
      expect(app.blocks.single.content['text'], 'Event notes');
    } finally {
      app.dispose();
      AppState.syncLogEnabled = true;
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // A platform file handle may still be closing.
      }
    }
  });

  test('a timeline reminder can be snoozed, rescheduled and dismissed', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final dir = Directory.systemTemp.createTempSync('onote_timeline_alarm_');
    final repo = await Repository.openAt(dir);
    final notebook = await repo.createNotebook('Timeline');
    AppState.syncLogEnabled = false;
    final app = AppState(repo);
    try {
      await app.selectNotebook(notebook.id);
      app.addTimeline(const Offset(100, 200));
      final block = app.blocks.single;
      final now = DateTime.now();
      final event = TimelineEvent(title: 'Send the report', day: now);
      app.saveTimelineEvent(block, event, changeReminder: true,
          reminderAt: now.subtract(const Duration(minutes: 1)));
      app.planner.startScheduler(now: now);
      final reminder = app.timelineReminder(block, event)!;
      expect(app.planner.pendingAlerts.single.title, 'Send the report');
      expect(reminder.blockId, block.id);
      expect(reminder.pageId, app.pageId);
      app.planner.snoozeAlert(reminder.id, const Duration(minutes: 10), now);
      expect(reminder.at, now.add(const Duration(minutes: 10)));
      expect(app.planner.pendingAlerts, isEmpty);

      app.planner.startScheduler(now: now.add(const Duration(minutes: 11)));
      expect(app.planner.pendingAlerts.single.id, reminder.id);
      final later = now.add(const Duration(days: 1));
      app.planner.rescheduleAlert(reminder.id, later);
      expect(reminder.at, later);
      expect(app.planner.pendingAlerts, isEmpty);
      app.planner.startScheduler(now: later.add(const Duration(minutes: 1)));
      app.planner.dismissAlert(reminder.id);
      expect(app.planner.pendingAlerts, isEmpty);
      expect(app.timelineReminder(block, event)!.dismissed, isTrue);
      app.removeTimelineEvent(block, event);
      expect(TimelineEvent.of(block), isEmpty);
      expect(app.timelineReminder(block, event), isNull);
    } finally {
      app.dispose();
      AppState.syncLogEnabled = true;
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // A platform file handle may still be closing.
      }
    }
  });
}
