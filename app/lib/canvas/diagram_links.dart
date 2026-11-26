import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';

Offset diagramAnchor(Rect rect, DiagramSide side) => switch (side) {
      DiagramSide.top => rect.topCenter,
      DiagramSide.right => rect.centerRight,
      DiagramSide.bottom => rect.bottomCenter,
      DiagramSide.left => rect.centerLeft,
    };

Offset _outward(DiagramSide side) => switch (side) {
      DiagramSide.top => const Offset(0, -1),
      DiagramSide.right => const Offset(1, 0),
      DiagramSide.bottom => const Offset(0, 1),
      DiagramSide.left => const Offset(-1, 0),
    };

Offset _edgeOf(Rect rect, Offset toward) {
  final delta = toward - rect.center;
  if (delta == Offset.zero) return rect.center;
  final scale = math.min(
    delta.dx == 0 ? double.infinity : rect.width / 2 / delta.dx.abs(),
    delta.dy == 0 ? double.infinity : rect.height / 2 / delta.dy.abs(),
  );
  return rect.center + delta * scale;
}

Path diagramPath(Rect from, Rect to, DiagramRoute route,
    {DiagramSide? fromSide, DiagramSide? toSide}) {
  final start = fromSide == null ? _edgeOf(from, to.center) : diagramAnchor(from, fromSide);
  final end = toSide == null ? _edgeOf(to, from.center) : diagramAnchor(to, toSide);
  final delta = end - start;
  final distance = delta.distance;
  final path = Path()..moveTo(start.dx, start.dy);
  if (distance < 1) return path;
  final along = delta / distance;
  final normal = Offset(-along.dy, along.dx);

  switch (route) {
    case DiagramRoute.straight:
      path.lineTo(end.dx, end.dy);
    case DiagramRoute.curved:
      final bend = normal * math.min(distance / 4, 60.0);
      final reach = math.min(distance * .4, 100.0);
      final first = fromSide == null
          ? start + delta * .28 + bend
          : start + _outward(fromSide) * reach;
      final last = toSide == null
          ? start + delta * .72 + bend
          : end + _outward(toSide) * reach;
      path.cubicTo(first.dx, first.dy, last.dx, last.dy, end.dx, end.dy);
    case DiagramRoute.wavy:
      final waves = (distance / 70).round().clamp(1, 30);
      final wavelength = distance / waves;
      final amplitude = math.min(14.0, wavelength / 3);
      for (var i = 0; i < waves; i++) {
        final origin = start + along * (i * wavelength);
        final first = origin + along * (wavelength / 3) + normal * amplitude;
        final last = origin + along * (wavelength * 2 / 3) - normal * amplitude;
        final next = origin + along * wavelength;
        path.cubicTo(first.dx, first.dy, last.dx, last.dy, next.dx, next.dy);
      }
    case DiagramRoute.elbow:
      if (delta.dx.abs() >= delta.dy.abs()) {
        final mid = (start.dx + end.dx) / 2;
        path.lineTo(mid, start.dy);
        path.lineTo(mid, end.dy);
      } else {
        final mid = (start.dy + end.dy) / 2;
        path.lineTo(start.dx, mid);
        path.lineTo(end.dx, mid);
      }
      path.lineTo(end.dx, end.dy);
  }
  return path;
}

class DiagramLinks extends StatelessWidget {
  const DiagramLinks({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final blocks = {for (final b in app.blocks) b.id: b};
    final links = <(DiagramConnection, Path, Offset)>[];
    for (final edge in app.pageProps.diagramConnections) {
      final from = blocks[edge.from], to = blocks[edge.to];
      if (from == null || to == null) continue;
      final path = diagramPath(app.blockRect(from), app.blockRect(to), edge.route,
          fromSide: edge.fromSide, toSide: edge.toSide);
      final metric = path.computeMetrics().firstOrNull;
      final labelAt = metric == null
          ? null
          : metric.getTangentForOffset(metric.length / 2)?.position;
      if (labelAt != null) links.add((edge, path, labelAt));
    }
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LinkPainter(links, colors.primary),
            ),
          ),
        ),
        for (final (edge, _, labelAt) in links)
          Positioned(
            left: labelAt.dx - 110,
            top: labelAt.dy - 24,
            width: 220,
            height: 48,
            child: Center(
              child: IgnorePointer(
                ignoring: app.inkToolInHand,
                child: Listener(
                  onPointerDown: (event) => app.claimedPointers.add(event.pointer),
                  child: Material(
                    color: colors.surface,
                    shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => showDiagramConnection(context, app, edge: edge),
                      child: Tooltip(
                        message: 'Edit connector',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          child: edge.label.isEmpty && edge.icon.isEmpty
                              ? Icon(Icons.link, size: 13, color: colors.primary)
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    [if (edge.icon.isNotEmpty) edge.icon, if (edge.label.isNotEmpty) edge.label].join(' '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DiagramAnchors extends StatefulWidget {
  const DiagramAnchors({
    super.key,
    required this.app,
    required this.visible,
    required this.scale,
  });

  final AppState app;
  final Rect visible;
  final double scale;

  @override
  State<DiagramAnchors> createState() => _DiagramAnchorsState();
}

class _DiagramAnchorsState extends State<DiagramAnchors> {
  int? _pointer;
  (String, DiagramSide)? _source;
  (String, DiagramSide)? _target;
  Offset? _position;

  double get _radius => 8 / widget.scale;
  double get _spacing => 8 + _radius;

  Offset _point(Rect rect, DiagramSide side) =>
      diagramAnchor(rect, side) + _outward(side) * _spacing;

  Offset _toPage(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  (String, DiagramSide)? _dropTarget(Offset at, String from) {
    (String, DiagramSide)? anchor;
    var distance = _radius * 2.5;
    Block? body;
    for (final block in widget.app.blocks) {
      if (block.id == from) continue;
      final rect = widget.app.blockRect(block);
      if (rect.inflate(_spacing + distance).contains(at)) {
        for (final side in DiagramSide.values) {
          final delta = (_point(rect, side) - at).distance;
          if (delta < distance) {
            distance = delta;
            anchor = (block.id, side);
          }
        }
      }
      if (rect.contains(at) && (body == null || block.z >= body.z)) {
        body = block;
      }
    }
    if (anchor != null || body == null) return anchor;
    final rect = widget.app.blockRect(body);
    final side = DiagramSide.values.reduce((a, b) =>
        (diagramAnchor(rect, a) - at).distanceSquared <=
                (diagramAnchor(rect, b) - at).distanceSquared ? a : b);
    return (body.id, side);
  }

  void _start(PointerDownEvent event, String id, DiagramSide side) {
    if (_pointer != null || (event.buttons & kPrimaryButton) == 0) return;
    widget.app.claimedPointers.add(event.pointer);
    setState(() {
      _pointer = event.pointer;
      _source = (id, side);
      _position = _toPage(event.position);
    });
  }

  void _move(PointerMoveEvent event) {
    final source = _source;
    if (_pointer != event.pointer || source == null) return;
    final point = _toPage(event.position);
    setState(() {
      _position = point;
      _target = _dropTarget(point, source.$1);
    });
  }

  void _clear(int pointer) {
    if (_pointer != pointer) return;
    setState(() {
      _pointer = null;
      _source = null;
      _target = null;
      _position = null;
    });
  }

  void _finish(PointerUpEvent event) {
    final source = _source;
    if (_pointer != event.pointer || source == null) return;
    final target = _dropTarget(_toPage(event.position), source.$1);
    _clear(event.pointer);
    if (target == null) return;
    showDiagramConnection(context, widget.app, from: source.$1,
        to: target.$1, fromSide: source.$2, toSide: target.$2);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    final source = _source, target = _target;
    final from = source == null ? null : app.blockById(source.$1);
    final to = target == null ? null : app.blockById(target.$1);
    final end = (to == null || target == null)
        ? _position
        : diagramAnchor(app.blockRect(to), target.$2);
    final active = [
      for (final b in app.blocks)
        if ((b.isDiagramCard || app.selectedIds.contains(b.id) ||
                b.id == source?.$1 || b.id == target?.$1) &&
            widget.visible.overlaps(app.blockRect(b).inflate(_spacing + _radius)))
          b,
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (from != null && source != null && end != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AnchorPreview(
                diagramAnchor(app.blockRect(from), source.$2), end,
                colors.primary, 2 / widget.scale,
              )),
            ),
          ),
        for (final b in active)
          for (final side in DiagramSide.values)
            _handle(b, side, colors, target == (b.id, side)),
      ],
    );
  }

  Widget _handle(Block b, DiagramSide side, ColorScheme colors, bool target) {
    final at = _point(widget.app.blockRect(b), side);
    return Positioned(
      key: ValueKey('connector-anchor-${b.id}-${side.name}'),
      left: at.dx - _radius,
      top: at.dy - _radius,
      width: _radius * 2,
      height: _radius * 2,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _start(event, b.id, side),
          onPointerMove: _move,
          onPointerUp: _finish,
          onPointerCancel: (event) => _clear(event.pointer),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: target ? colors.primary : colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.primary, width: 1.6 / widget.scale),
              ),
              child: SizedBox.square(dimension: _radius * 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchorPreview extends CustomPainter {
  const _AnchorPreview(this.start, this.end, this.color, this.width);

  final Offset start;
  final Offset end;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(start, end, Paint()..color = color..strokeWidth = width);
  }

  @override
  bool shouldRepaint(covariant _AnchorPreview oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end ||
      color != oldDelegate.color || width != oldDelegate.width;
}

class _LinkPainter extends CustomPainter {
  _LinkPainter(this.links, this.color);

  final List<(DiagramConnection, Path, Offset)> links;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final (edge, path, _) in links) {
      paint.strokeWidth = edge.stroke == DiagramStroke.doubleLine ? 1.6 : 2.4;
      if (edge.stroke == DiagramStroke.solid) {
        canvas.drawPath(path, paint);
        continue;
      }
      for (final metric in path.computeMetrics()) {
        if (edge.stroke == DiagramStroke.doubleLine) {
          for (final offset in [-2.4, 2.4]) {
            final rail = Path();
            final samples = math.max(1, (metric.length / 3).ceil());
            for (var i = 0; i <= samples; i++) {
              final tangent = metric.getTangentForOffset(metric.length * i / samples);
              if (tangent == null) continue;
              final direction = tangent.vector;
              final point = tangent.position + Offset(-direction.dy, direction.dx) * offset;
              if (i == 0) {
                rail.moveTo(point.dx, point.dy);
              } else {
                rail.lineTo(point.dx, point.dy);
              }
            }
            canvas.drawPath(rail, paint);
          }
        } else {
          final dotted = edge.stroke == DiagramStroke.dotted;
          final dash = dotted ? .2 : 8.0;
          final period = dotted ? 5.0 : 13.0;
          for (var at = 0.0; at < metric.length; at += period) {
            canvas.drawPath(
                metric.extractPath(at, math.min(at + dash, metric.length)), paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinkPainter oldDelegate) => true;
}

String _title(AppState app, Block block) {
  final label = block.content['text'] ?? block.content['name'];
  if (label is String && label.trim().isNotEmpty) {
    return label.trim().split('\n').first;
  }
  final page = block.diagramCanvasPageId;
  if (page != null) return app.node(page)?.title ?? 'Card canvas';
  return block.isDiagramCard ? 'Diagram card' : block.type.name;
}

Future<void> showDiagramConnection(BuildContext context, AppState app,
    {String? from, String? to, DiagramSide? fromSide, DiagramSide? toSide,
    DiagramConnection? edge}) async {
  final start = edge?.from ?? from;
  if (start == null) return;
  final hostPage = app.pageId;
  final targets = {
    for (final card in app.blocks)
      if (card.id != start) card.id: _title(app, card),
  };
  if (targets.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Add another object to connect.')));
    return;
  }
  final draft = to == null ? null : DiagramConnection(
      from: start, to: to, fromSide: fromSide, toSide: toSide);
  final result = await showDialog<(DiagramConnection?, bool)>(
    context: context,
    builder: (_) => _ConnectionDialog(
        from: start, targets: targets, initial: edge ?? draft, existing: edge != null),
  );
  if (result == null || app.pageId != hostPage) return;
  final (connector, remove) = result;
  if (remove && edge != null) {
    app.removeDiagramConnection(edge.id);
  } else if (connector != null) {
    app.saveDiagramConnection(connector);
  }
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({required this.from, required this.targets,
    required this.existing, this.initial});

  final String from;
  final Map<String, String> targets;
  final DiagramConnection? initial;
  final bool existing;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _icon = TextEditingController(text: widget.initial?.icon ?? '');
  late String _target = widget.targets.containsKey(widget.initial?.to)
      ? widget.initial!.to
      : widget.targets.keys.first;
  late DiagramRoute _route = widget.initial?.route ?? DiagramRoute.straight;
  late DiagramStroke _stroke = widget.initial?.stroke ?? DiagramStroke.solid;

  @override
  void dispose() {
    _label.dispose();
    _icon.dispose();
    super.dispose();
  }

  String _routeLabel(DiagramRoute route) => switch (route) {
        DiagramRoute.straight => 'Straight',
        DiagramRoute.curved => 'Curved',
        DiagramRoute.wavy => 'Wavy',
        DiagramRoute.elbow => 'Right angle',
      };

  String _strokeLabel(DiagramStroke stroke) => switch (stroke) {
        DiagramStroke.solid => 'Solid',
        DiagramStroke.dashed => 'Dashed',
        DiagramStroke.dotted => 'Dotted',
        DiagramStroke.doubleLine => 'Double',
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing ? 'Edit connector' : 'Connect objects'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _target,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Connect to'),
                items: [
                  for (final target in widget.targets.entries)
                    DropdownMenuItem(
                      value: target.key,
                      child: Text(target.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _target = value ?? _target),
              ),
              TextField(
                controller: _label,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Text on line'),
              ),
              TextField(
                controller: _icon,
                maxLength: 8,
                decoration: const InputDecoration(
                    labelText: 'Icon or emoji', hintText: '★, →, ✓'),
              ),
              DropdownButtonFormField<DiagramRoute>(
                initialValue: _route,
                decoration: const InputDecoration(labelText: 'Path'),
                items: [
                  for (final route in DiagramRoute.values)
                    DropdownMenuItem(value: route, child: Text(_routeLabel(route))),
                ],
                onChanged: (value) => setState(() => _route = value ?? _route),
              ),
              DropdownButtonFormField<DiagramStroke>(
                initialValue: _stroke,
                decoration: const InputDecoration(labelText: 'Line style'),
                items: [
                  for (final stroke in DiagramStroke.values)
                    DropdownMenuItem(value: stroke, child: Text(_strokeLabel(stroke))),
                ],
                onChanged: (value) => setState(() => _stroke = value ?? _stroke),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.existing)
            TextButton(
              onPressed: () => Navigator.of(context).pop((null, true)),
              child: const Text('Remove connector'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              DiagramConnection(
                id: widget.initial?.id,
                from: widget.from,
                to: _target,
                fromSide: widget.initial?.fromSide,
                toSide: _target == widget.initial?.to ? widget.initial?.toSide : null,
                label: _label.text.trim(),
                icon: _icon.text.trim(),
                route: _route,
                stroke: _stroke,
              ),
              false,
            )),
            child: const Text('Save'),
          ),
        ],
      );
}
