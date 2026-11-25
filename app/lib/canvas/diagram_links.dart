import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';

Rect _cardRect(Block block) =>
    Rect.fromLTWH(block.x, block.y, block.w, block.h ?? 200);

Offset _edgeOf(Rect rect, Offset toward) {
  final delta = toward - rect.center;
  if (delta == Offset.zero) return rect.center;
  final scale = math.min(
    delta.dx == 0 ? double.infinity : rect.width / 2 / delta.dx.abs(),
    delta.dy == 0 ? double.infinity : rect.height / 2 / delta.dy.abs(),
  );
  return rect.center + delta * scale;
}

Path diagramPath(Rect from, Rect to, DiagramRoute route) {
  final start = _edgeOf(from, to.center);
  final end = _edgeOf(to, from.center);
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
      final first = start + delta * .28 + bend;
      final last = start + delta * .72 + bend;
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
    final cards = {for (final b in app.blocks) if (b.isDiagramCard) b.id: b};
    final links = <(DiagramConnection, Path, Offset)>[];
    for (final edge in app.pageProps.diagramConnections) {
      final from = cards[edge.from], to = cards[edge.to];
      if (from == null || to == null) continue;
      final path = diagramPath(_cardRect(from), _cardRect(to), edge.route);
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

String _title(AppState app, Block card) {
  final ref = card.content['ref'];
  final pageId = ref is Map ? ref['pageId'] : null;
  return pageId is String
      ? app.node(pageId)?.title ?? 'Card canvas'
      : 'Card canvas';
}

Future<void> showDiagramConnection(BuildContext context, AppState app,
    {String? from, DiagramConnection? edge}) async {
  final start = edge?.from ?? from;
  if (start == null) return;
  final hostPage = app.pageId;
  final targets = {
    for (final card in app.blocks)
      if (card.isDiagramCard && card.id != start) card.id: _title(app, card),
  };
  if (targets.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Add a second diagram card first.')));
    return;
  }
  final result = await showDialog<(DiagramConnection?, bool)>(
    context: context,
    builder: (_) => _ConnectionDialog(from: start, targets: targets, edge: edge),
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
  const _ConnectionDialog({required this.from, required this.targets, this.edge});

  final String from;
  final Map<String, String> targets;
  final DiagramConnection? edge;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final _label = TextEditingController(text: widget.edge?.label ?? '');
  late final _icon = TextEditingController(text: widget.edge?.icon ?? '');
  late String _target = widget.targets.containsKey(widget.edge?.to)
      ? widget.edge!.to
      : widget.targets.keys.first;
  late DiagramRoute _route = widget.edge?.route ?? DiagramRoute.straight;
  late DiagramStroke _stroke = widget.edge?.stroke ?? DiagramStroke.solid;

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
        title: Text(widget.edge == null ? 'Connect cards' : 'Edit connector'),
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
          if (widget.edge != null)
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
                id: widget.edge?.id,
                from: widget.from,
                to: _target,
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
