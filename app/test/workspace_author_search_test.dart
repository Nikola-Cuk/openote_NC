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
      block.content['text'] = 'Cross notebook test token updated';
      app.updateBlock(block);
      await app.flushSave();
      final authors = repo.readPage(active.id, page).blocks.single.attribution;
      expect(authors.created?.initials, 'NC');
      expect(authors.edited?.initials, 'AI');
      expect(authors.edited!.at, greaterThanOrEqualTo(authors.created!.at));

      await app.selectNotebook(other.id);
      expect(app.searchNotebook(active, 'test token').single.nodeId, page);
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
