import 'dart:math' as math;
import 'dart:ui' as ui show PathMetric;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import 'object_chrome.dart';

const _anchorGap = 4.0;

Offset diagramAnchor(Rect rect, DiagramSide side) {
  final edge = switch (side) {
    // Keep midpoint dragging available for the move bar and resize grips.
    DiagramSide.top => Offset(rect.left + rect.width * .23, rect.top),
    DiagramSide.right => Offset(rect.right, rect.top + rect.height * .23),
    DiagramSide.bottom => Offset(rect.left + rect.width * .23, rect.bottom),
    DiagramSide.left => Offset(rect.left, rect.top + rect.height * .23),
  };
  return edge + _outward(side) * _anchorGap;
}

Offset _outward(DiagramSide side) => switch (side) {
      DiagramSide.top => const Offset(0, -1),
      DiagramSide.right => const Offset(1, 0),
      DiagramSide.bottom => const Offset(0, 1),
      DiagramSide.left => const Offset(-1, 0),
    };

DiagramSide _sideToward(Rect rect, Offset toward) {
  final delta = toward - rect.center;
  if (delta.dx.abs() * rect.height >= delta.dy.abs() * rect.width) {
    return delta.dx < 0 ? DiagramSide.left : DiagramSide.right;
  }
  return delta.dy < 0 ? DiagramSide.top : DiagramSide.bottom;
}

Path diagramPath(Rect from, Rect to, DiagramRoute route,
    {DiagramSide? fromSide, DiagramSide? toSide}) {
  final start = diagramAnchor(from, fromSide ?? _sideToward(from, to.center));
  final end = diagramAnchor(to, toSide ?? _sideToward(to, from.center));
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

typedef _DiagramLink = (DiagramConnection, Path, Offset, Offset);

class DiagramLinks extends StatefulWidget {
  const DiagramLinks({super.key, required this.app, required this.visible});

  final AppState app;
  final Rect visible;

  @override
  State<DiagramLinks> createState() => _DiagramLinksState();
}

class _DiagramLinksState extends State<DiagramLinks>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final blocks = {for (final b in app.blocks) b.id: b};
    final links = <_DiagramLink>[];
    for (final edge in app.pageProps.diagramConnections) {
      final from = blocks[edge.from], to = blocks[edge.to];
      if (from == null || to == null) continue;
      final path = diagramPath(canvasObjectFrame(app, from),
          canvasObjectFrame(app, to), edge.route,
          fromSide: edge.fromSide, toSide: edge.toSide);
      if (!path.getBounds().inflate(32).overlaps(widget.visible)) continue;
      final metric = path.computeMetrics().firstOrNull;
      if (metric == null) continue;
      final middle = metric.getTangentForOffset(metric.length / 2);
      if (middle == null) continue;
      links.add((edge, path, middle.position, middle.vector));
    }
    final steady = links.where((link) => link.$1.flow == DiagramFlow.none).toList();
    final flowing = links.where((link) => link.$1.flow != DiagramFlow.none).toList();
    final animate = flowing.isNotEmpty && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_phase.isAnimating) _phase.repeat();
    if (!animate && _phase.isAnimating) _phase.stop();
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (steady.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _LinkPainter(steady, colors.primary)),
            ),
          ),
        if (flowing.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _FlowPainter(flowing, colors.primary, colors.surface,
                      animate ? _phase : null),
                  willChange: animate,
                ),
              ),
            ),
          ),
        for (final (edge, _, labelAt, direction) in links)
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
                  child: _ConnectorBadge(
                    edge: edge,
                    direction: direction,
                    showAuthor: app.showAuthorBadges,
                    onEdit: () => showDiagramConnection(context, app, edge: edge),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectorBadge extends StatelessWidget {
  const _ConnectorBadge({required this.edge, required this.direction,
    required this.showAuthor, required this.onEdit});

  final DiagramConnection edge;
  final Offset direction;
  final bool showAuthor;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final flowing = edge.flow != DiagramFlow.none;
    final label = [
      if (edge.icon.isNotEmpty) edge.icon,
      if (edge.label.isNotEmpty) edge.label,
    ].join(' ');
    return CustomPaint(
      painter: _BadgeHull(
        direction: direction,
        pipeWidth: flowing ? 2.4 * edge.flowWidth : 0,
        fill: flowing ? _pipeFill(colors.primary, colors.surface) : colors.surface,
        border: flowing ? _pipeBorder(colors.primary) : colors.outlineVariant,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onEdit,
                child: Tooltip(
                  message: 'Edit connector',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: label.isEmpty
                        ? Icon(Icons.link, size: 13, color: colors.primary)
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 172),
                            child: Text(label, maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11)),
                          ),
                  ),
                ),
              ),
              if (showAuthor && edge.attribution.latest != null)
                CanvasAuthorBadge(attribution: edge.attribution),
            ],
          ),
        ),
      ),
    );
  }
}

Color _pipeFill(Color color, Color surface) =>
    Color.alphaBlend(color.withValues(alpha: .17), surface);

Color _pipeBorder(Color color) => color.withValues(alpha: .48);

class _BadgeHull extends CustomPainter {
  const _BadgeHull({required this.direction, required this.pipeWidth,
    required this.fill, required this.border});

  final Offset direction;
  final double pipeWidth;
  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var hull = Path()..addRRect(RRect.fromRectAndRadius(
        rect, Radius.circular(size.height / 2)));
    if (pipeWidth > 0) {
      final center = rect.center;
      final normal = Offset(-direction.dy, direction.dx);
      final rim = math.min(
        direction.dx == 0 ? double.infinity : size.width / 2 / direction.dx.abs(),
        direction.dy == 0 ? double.infinity : size.height / 2 / direction.dy.abs(),
      );
      final tip = direction * (rim + 12);
      final shoulder = direction * (rim * .56);
      final narrow = normal * (pipeWidth / 2);
      final wide = normal * math.min(size.height * .38, rim * .69);
      final a = center - tip + narrow, b = center + tip + narrow;
      final c = center + tip - narrow, d = center - tip - narrow;
      final ab = center + wide, cd = center - wide;
      final join = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo((center - shoulder + narrow).dx,
            (center - shoulder + narrow).dy, ab.dx, ab.dy)
        ..quadraticBezierTo((center + shoulder + narrow).dx,
            (center + shoulder + narrow).dy, b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..quadraticBezierTo((center + shoulder - narrow).dx,
            (center + shoulder - narrow).dy, cd.dx, cd.dy)
        ..quadraticBezierTo((center - shoulder - narrow).dx,
            (center - shoulder - narrow).dy, d.dx, d.dy)
        ..close();
      hull = Path.combine(PathOperation.union, hull, join);
    }
    canvas
      ..drawPath(hull, Paint()..color = fill)
      ..drawPath(hull, Paint()..color = border..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _BadgeHull old) =>
      old.direction != direction || old.pipeWidth != pipeWidth ||
      old.fill != fill || old.border != border;
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

  double get _radius => math.min(12.0, 8 / widget.scale);

  Offset _toPage(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  (String, DiagramSide)? _dropTarget(Offset at, String from) {
    (String, DiagramSide)? anchor;
    var distance = _radius * 2.5;
    Block? body;
    for (final block in widget.app.blocks) {
      if (block.id == from || !block.canAnchor) continue;
      final rect = canvasObjectFrame(widget.app, block);
      if (rect.inflate(_anchorGap + distance).contains(at)) {
        for (final side in DiagramSide.values) {
          final delta = (diagramAnchor(rect, side) - at).distance;
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
    final rect = canvasObjectFrame(widget.app, body);
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
        : diagramAnchor(canvasObjectFrame(app, to), target.$2);
    final active = [
      for (final b in app.blocks)
        if (b.canAnchor && (b.isDiagramCard || app.selectedIds.contains(b.id) ||
                b.id == source?.$1 || b.id == target?.$1) &&
            widget.visible.overlaps(canvasObjectFrame(app, b).inflate(_anchorGap + _radius)))
          b,
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (from != null && source != null && end != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AnchorPreview(
                diagramAnchor(canvasObjectFrame(app, from), source.$2), end,
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
    final rect = canvasObjectFrame(widget.app, b);
    final at = diagramAnchor(rect, side);
    final edgeLength = _outward(side).dx == 0 ? rect.width : rect.height;
    final radius = math.min(_radius, math.max(3.0, edgeLength * .27 - 1));
    return Positioned(
      key: ValueKey('connector-anchor-${b.id}-${side.name}'),
      left: at.dx - radius,
      top: at.dy - radius,
      width: radius * 2,
      height: radius * 2,
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
              child: SizedBox.square(dimension: radius * 1.4),
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

  final List<_DiagramLink> links;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final (edge, path, _, _) in links) {
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

class _FlowPainter extends CustomPainter {
  _FlowPainter(List<_DiagramLink> links, this.color, this.surface, this.phase)
      : lines = [
          for (final (edge, path, _, _) in links)
            (edge, path, path.computeMetrics().toList()),
        ],
        super(repaint: phase);

  final List<(DiagramConnection, Path, List<ui.PathMetric>)> lines;
  final Color color;
  final Color surface;
  final Animation<double>? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = _pipeBorder(color)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final pipe = Paint()
      ..color = _pipeFill(color, surface)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    const gap = 14.0;
    final travel = ((phase?.value ?? .5) % 1) * gap;
    for (final (edge, path, metrics) in lines) {
      final width = 2.4 * edge.flowWidth;
      outline.strokeWidth = width + 1.5;
      pipe.strokeWidth = width;
      arrow.strokeWidth = width * .18;
      canvas.drawPath(path, outline);
      canvas.drawPath(path, pipe);
      final forward = edge.flow == DiagramFlow.forward;
      for (final metric in metrics) {
        final length = metric.length;
        if (length < 7) continue;
        final fade = math.min(22.0, length / 2);
        for (var progressed = travel; progressed < length; progressed += gap) {
          final tangent = metric.getTangentForOffset(
              forward ? progressed : length - progressed);
          if (tangent == null) continue;
          final direction = forward ? tangent.vector : -tangent.vector;
          final normal = Offset(-direction.dy, direction.dx);
          final middle = tangent.position;
          final tip = middle + direction * (width * .37);
          final tail = middle - direction * (width * .34);
          final rise = normal * (width * .27);
          final start = tail + rise, end = tail - rise;
          final opacity = math.min(progressed, length - progressed) / fade;
          final fadeInOut = opacity.clamp(0.0, 1.0);
          arrow.color = color.withValues(
              alpha: .95 * fadeInOut * fadeInOut * (3 - 2 * fadeInOut));
          canvas.drawPath(
            Path()..moveTo(start.dx, start.dy)
              ..lineTo(tip.dx, tip.dy)..lineTo(end.dx, end.dy),
            arrow,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) => true;
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
      if (card.id != start && card.canAnchor) card.id: _title(app, card),
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
  late DiagramFlow _flow = widget.initial?.flow ?? DiagramFlow.none;
  late int _flowWidth = widget.initial?.flowWidth ?? 3;

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

  String _flowLabel(DiagramFlow flow) => switch (flow) {
        DiagramFlow.none => 'Off',
        DiagramFlow.forward => 'Forward',
        DiagramFlow.reverse => 'Reverse',
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
              DropdownButtonFormField<DiagramFlow>(
                initialValue: _flow,
                decoration: const InputDecoration(labelText: 'Arrow flow'),
                items: [
                  for (final flow in DiagramFlow.values)
                    DropdownMenuItem(value: flow, child: Text(_flowLabel(flow))),
                ],
                onChanged: (value) => setState(() => _flow = value ?? _flow),
              ),
              if (_flow == DiagramFlow.none)
                DropdownButtonFormField<DiagramStroke>(
                  initialValue: _stroke,
                  decoration: const InputDecoration(labelText: 'Line style'),
                  items: [
                    for (final stroke in DiagramStroke.values)
                      DropdownMenuItem(value: stroke, child: Text(_strokeLabel(stroke))),
                  ],
                  onChanged: (value) => setState(() => _stroke = value ?? _stroke),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _flowWidth,
                  decoration: const InputDecoration(labelText: 'Flow width'),
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2×')),
                    DropdownMenuItem(value: 3, child: Text('3×')),
                  ],
                  onChanged: (value) =>
                      setState(() => _flowWidth = value ?? _flowWidth),
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
                flow: _flow,
                flowWidth: _flowWidth,
              ),
              false,
            )),
            child: const Text('Save'),
          ),
        ],
      );
}
