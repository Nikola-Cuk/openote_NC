// Two canvas-feel asks from PLANNING.md, pinned:
//
//   "On touch screens, by default dragging with a finger should pan around
//    the page, it shouldn't be the selector tool."
//   "[Boxes] should automatically stop growing before going off the screen
//    (with a small amount of buffer room)."
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('where an auto-width box stops growing', () {
    test('far from the edge, the ordinary clamp wins and the edge is moot', () {
      expect(autoWidthEdgeCap(blockX: 100, viewportRightPage: 2000), isNull);
    });

    test('near the edge, the box stops a buffer short of it', () {
      expect(autoWidthEdgeCap(blockX: 600, viewportRightPage: 1000),
          1000 - 24 - 600);
    });

    test('hard against the edge, a usable minimum beats a sliver', () {
      expect(autoWidthEdgeCap(blockX: 990, viewportRightPage: 1000),
          TextBlockView.minAutoW,
          reason: 'a 10px text box is worse than poking past the edge');
    });
  });

  group('on the canvas', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_canvas_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Canvas');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester t, {bool listen = false}) async {
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: listen
                ? ListenableBuilder(
                    listenable: app,
                    builder: (context, child) => PageCanvas(state: app),
                  )
                : PageCanvas(state: app),
          ),
        ),
      ));
      await t.pump(); // the post-frame view restore
      await t.pump();
    }

    testWidgets('a locked text box displays selectable text and unlocks from its bar',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = app.addBlock(Block(
        type: BlockType.text,
        x: 150,
        y: 200,
        w: 280,
        content: {'text': 'Protected text', 'autoWidth': false},
      ));
      app.setTextBlockLocked(b.id, locked: true);
      await pump(t, listen: true);

      expect(find.byType(SelectionArea), findsOneWidget);
      final lock = find.byTooltip('Text block locked. Click to unlock.');
      expect(lock, findsOneWidget);
      await t.tap(lock);
      await t.pump();
      expect(b.textLocked, isFalse);
      expect(lock, findsNothing);
      expect(find.byType(SelectionArea), findsNothing);

      app.select(b.id, edit: true);
      await t.pump();
      expect(app.editingBlockId, b.id);
      app.cancelPendingSave();
    });

    testWidgets('dragging a card anchor connects an ordinary text box',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.addDiagramCard(const Offset(64, 180));
      final card = app.blocks.single;
      final note = app.addBlock(Block(
        type: BlockType.text,
        x: 470,
        y: 220,
        w: 180,
        content: {'text': 'Other block', 'autoWidth': false},
      ));
      app.select(null);
      await pump(t, listen: true);

      for (final side in DiagramSide.values) {
        expect(find.byKey(ValueKey('connector-anchor-${card.id}-${side.name}')),
            findsOneWidget);
      }
      final from = find.byKey(ValueKey('connector-anchor-${card.id}-right'));
      final target = find.byKey(ValueKey('${note.id}#${app.docRevision}'));
      final start = t.getCenter(from);
      final end = t.getCenter(target);
      final gesture = await t.startGesture(start, kind: PointerDeviceKind.mouse);
      await gesture.moveTo(end);
      await t.pump();
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.text('Connect objects'), findsOneWidget);

      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final edge = app.pageProps.diagramConnections.single;
      expect(edge.from, card.id);
      expect(edge.to, note.id);
      expect(edge.fromSide, DiagramSide.right);
      expect(edge.toSide, isNotNull);
      app.cancelPendingSave();
    });

    testWidgets('bottom handle fixes the height of a normal text box', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final note = app.addBlock(Block(
        type: BlockType.text,
        x: 100,
        y: 180,
        w: 240,
        content: {'text': 'Resizable', 'autoWidth': false},
      ));
      app.select(note.id);
      await pump(t, listen: true);
      final bottom = find.byKey(ValueKey('resize-height-${note.id}'));
      expect(bottom, findsOneWidget);
      final before = app.blockRect(note).height;
      await t.drag(bottom, const Offset(0, 85), kind: PointerDeviceKind.mouse);
      await t.pumpAndSettle();
      expect(note.h, greaterThan(before));
      app.cancelPendingSave();
    });

    testWidgets('A FINGER DRAG PANS; IT DOES NOT MARQUEE', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A block that a marquee from the centre would certainly catch, so a
      // wrong turn in the drag routing shows up as a selection.
      app.addBlock(Block(
          type: BlockType.text,
          x: 200,
          y: 200,
          w: 300,
          content: {'text': 'catch me', 'autoWidth': false}));
      app.select(null);
      await pump(t);

      final before = app.canvas.offset;
      final g = await t.startGesture(const Offset(400, 300),
          kind: PointerDeviceKind.touch);
      await g.moveBy(const Offset(-120, -60));
      await t.pump();
      await g.up();
      await t.pump();

      expect(app.canvas.offset, isNot(before),
          reason: 'the page moved under the finger');
      expect(app.selectedIds, isEmpty,
          reason: 'and nothing was marquee-selected on the way');
      app.cancelPendingSave();
    });

    testWidgets('DRAGGING THE SCROLL BAR SCROLLS — IT DOES NOT MARQUEE',
        (t) async {
      // The canvas's select handler is a raw Listener, outside the gesture
      // arena — so the bar's GestureDetector winning meant nothing to it,
      // and a drag on the track was also a marquee: "it draws up a box
      // behind it as it goes up". The bar now claims its pointers.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Content far below the fold, so the page is taller than the window
      // (the bar only exists then) and a stray marquee would catch nothing —
      // the tell is the pending→marquee mode itself selecting NOTHING while
      // the page also fails to move. Selection empty AND offset moved is
      // the pass.
      app.addBlock(Block(
          type: BlockType.text,
          x: 100,
          y: 2400,
          w: 300,
          content: {'text': 'far below', 'autoWidth': false}));
      app.select(null);
      await pump(t);

      final before = app.canvas.offset;
      final g = await t.startGesture(const Offset(794, 100),
          kind: PointerDeviceKind.mouse);
      await t.pump();
      // Several small moves, as a real mouse produces: a single big jump is
      // swallowed whole by the drag recognizer's ACCEPT and never arrives
      // as an update.
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(0, 30));
        await t.pump();
      }
      await g.up();
      await t.pump();

      expect(app.canvas.offset.dy, lessThan(before.dy),
          reason: 'dragging the thumb down scrolls the page down');
      expect(app.selectedIds, isEmpty,
          reason: 'and no marquee ran behind the bar');
      app.cancelPendingSave();
    });

    testWidgets('a mouse drag still marquees', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = app.addBlock(Block(
          type: BlockType.text,
          x: 200,
          y: 300,
          w: 200,
          h: 60,
          content: {'text': 'catch me', 'autoWidth': false}));
      app.select(null);
      await pump(t);

      // Drag a screen rect that certainly covers the block, computed from the
      // live transform so the zoom the canvas restored does not matter.
      final tl = app.canvas.pageToScreen(const Offset(150, 250));
      final br = app.canvas.pageToScreen(const Offset(450, 400));
      final g = await t.startGesture(tl, kind: PointerDeviceKind.mouse);
      await g.moveTo(br);
      await t.pump();
      await g.up();
      await t.pump();

      expect(app.selectedIds, contains(b.id),
          reason: 'pen and mouse keep the selector drag');
      app.cancelPendingSave();
    });
  });
}
