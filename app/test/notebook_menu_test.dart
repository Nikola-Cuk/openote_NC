// The notebook bar must open the ONE notebook surface.
//
// Regression guard for the "two different menus for one thing" report: there
// used to be a dropdown (switching) *and* a manager panel (everything else).
// Tapping the bar now opens the manager, which both switches and manages, so
// there is exactly one surface — and no `MenuAnchor` left in the navigator's
// notebook area to reintroduce the second one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  testWidgets('tapping the notebook bar opens the single notebook surface',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    late Repository repo;
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('onote_menu_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final a = await repo.createNotebook('Alpha');
      await repo.createNotebook('Beta');
      app = AppState(repo)..notebookId = a.id;
      app.nodes = repo.loadNodes(a.id);
      app.activeSectionId =
          app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: Sidebar(app: app)),
    ));
    await tester.pumpAndSettle();

    // Exactly one notebook affordance, and it is not a dropdown menu.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byType(MenuAnchor), findsNothing,
        reason: 'the notebook dropdown was replaced by the manager');

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // The manager is open: it lists BOTH notebooks (so it can switch) and offers
    // the management actions (so it is the single surface).
    expect(find.text('Notebooks'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('top navigator keeps search results across notebook switches',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final tmp = Directory.systemTemp.createTempSync('onote_top_nav_');
    late AppState app;
    late String alphaId;
    late String betaId;
    late String alphaPage;
    late String betaPage;
    late String alternateSection;
    AppState.syncLogEnabled = false;
    addTearDown(() {
      app.dispose();
      AppState.syncLogEnabled = true;
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // A platform file handle may still be closing.
      }
    });
    await tester.runAsync(() async {
      final repo = await Repository.openAt(tmp);
      alphaId = (await repo.createNotebook('Alpha')).id;
      betaId = (await repo.createNotebook('Beta')).id;
      app = AppState(repo);
      await app.selectNotebook(betaId);
      betaPage = app.pageId!;
      app.renameNode(betaPage, 'Match second');
      await app.selectNotebook(alphaId);
      alphaPage = app.pageId!;
      app.renameNode(alphaPage, 'Match first');
      await app.addSection();
      alternateSection = app.activeSectionId!;
      app.renameNode(alternateSection, 'Alternate section');
      await app.selectPage(alphaPage);
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Column(children: [
          ListenableBuilder(
            listenable: app,
            builder: (context, _) => Sidebar(app: app, top: true),
          ),
          const Expanded(child: SizedBox()),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final book = find.byKey(const ValueKey('notebook-picker'));
    final section = find.byKey(const ValueKey('section-picker'));
    final search = find.byKey(const ValueKey('notebook-search'));
    final results = find.byKey(const ValueKey('notebook-search-results'));
    expect(tester.getTopLeft(book).dy,
        lessThan(tester.getTopLeft(find.text('Match first')).dy));
    await tester.tap(section);
    await tester.pumpAndSettle();
    expect(find.text('Alternate section'), findsOneWidget);
    await tester.tapAt(const Offset(5, 300));
    await tester.pumpAndSettle();
    expect(app.activeSectionId, isNot(alternateSection));

    await tester.enterText(search, 'Match');
    await tester.pumpAndSettle();
    final first = find.text('Alpha > Section 1 > Match first');
    final second = find.text('Beta > Section 1 > Match second');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(second);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(app.notebookId, betaId);
    expect(app.pageId, betaPage);
    expect(results, findsOneWidget);
    expect(first, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    await tester.runAsync(() async {
      await tester.tap(first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(app.notebookId, alphaId);
    expect(app.pageId, alphaPage);
    expect(tester.widget<TextField>(search).controller!.text, 'Match');
    expect(second, findsOneWidget);
    app.cancelPendingSave();
  });
}
