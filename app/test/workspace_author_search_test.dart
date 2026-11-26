import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var sqlite = false;
  setUpAll(() => sqlite = initSqliteForTests());

  test('attribution persists across saves and search respects other notebook passcodes',
      () async {
    if (!sqlite) return markTestSkipped('sqlite unavailable');
    final dir = Directory.systemTemp.createTempSync('openote_author_search_');
    final repo = await Repository.openAt(dir);
    final active = await repo.createNotebook('Active');
    final other = await repo.createNotebook('Other');
    final app = AppState(repo);
    AppState.syncLogEnabled = false;
    try {
      await app.selectNotebook(active.id);
      app.setAuthorProfile('Nikola Cuk', showBadges: false);
      expect(app.authorInitials, 'NC');
      expect(app.showAuthorBadges, false);
      final page = app.pageId!;
      final block = app.addBlock(Block(
        type: BlockType.text, x: 150, y: 260,
        content: {'text': 'Cross notebook test token'},
      ));
      await app.flushSave();
      expect(repo.readPage(active.id, page).blocks.single.attribution.created?.initials, 'NC');

      app.setAuthorProfile('Ana Ilic', showBadges: true);
      app.select(block.id);
      app.moveSelectedBy(28, 15);
      await app.flushSave();
      final moved = repo.readPage(active.id, page).blocks.single;
      expect(moved.x, block.x);
      expect(moved.y, block.y);
      expect(moved.attribution.created?.initials, 'NC');
      expect(moved.attribution.edited, isNull);

      block.content['text'] = 'First occurrence of test token followed by '
          'enough context to leave distinct snippets for the next occurrence of test token.';
      app.updateBlock(block);
      await app.flushSave();
      final authors = repo.readPage(active.id, page).blocks.single.attribution;
      expect(authors.created?.initials, 'NC');
      expect(authors.edited?.initials, 'AI');
      expect(authors.edited!.at, greaterThanOrEqualTo(authors.created!.at));

      final otherBlock = app.addBlock(Block(
        type: BlockType.text, x: 400, y: 260,
        content: {'text': 'Connector target'},
      ));
      await app.flushSave();
      app.setAuthorProfile('Petar Petrovic');
      final edge = DiagramConnection(from: block.id, to: otherBlock.id);
      app.saveDiagramConnection(edge);
      await app.flushSave();
      expect(repo.readPage(active.id, page).blocks
          .firstWhere((b) => b.id == block.id).attribution.edited?.initials, 'PP');

      app.setAuthorProfile('Ana Ilic');
      app.saveDiagramConnection(edge);
      app.select(block.id);
      app.moveSelectedBy(20, 0);
      await app.flushSave();
      final connected = repo.readPage(active.id, page);
      expect(connected.blocks.firstWhere((b) => b.id == block.id)
          .attribution.edited?.initials, 'PP');
      expect(connected.props.diagramConnections.single.attribution.edited, isNull);

      app.removeDiagramConnection(edge.id);
      await app.flushSave();
      expect(repo.readPage(active.id, page).blocks
          .firstWhere((b) => b.id == block.id).attribution.edited?.initials, 'AI');

      await app.selectNotebook(other.id);
      final hits = app.searchNotebook(active, 'test token');
      expect(hits, hasLength(2));
      expect(hits.map((hit) => hit.nodeId), everyElement(page));
      expect(hits.map((hit) => hit.breadcrumb),
          everyElement('Active > Section 1 > Untitled page'));
      expect(hits.first.subtitle, contains('First occurrence'));
      expect(hits.last.subtitle, contains('next occurrence'));
      await app.selectNotebook(active.id);
      app.protectNode(page, '12345', UnlockPolicy.session);
      await app.selectNotebook(other.id);
      expect(app.searchNotebook(active, 'test token'), isEmpty);
    } finally {
      app.dispose();
      AppState.syncLogEnabled = true;
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // A background platform handle can finish closing after the test.
      }
    }
  });
}
