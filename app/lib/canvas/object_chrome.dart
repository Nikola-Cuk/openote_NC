import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../model/models.dart';
import '../state/app_state.dart';

Rect canvasObjectFrame(AppState app, Block block) {
  final body = app.blockRect(block);
  final width = block.type == BlockType.ink ? math.max(body.width, 48.0) : body.width;
  final header = app.canvasHeaderSize.height;
  return Rect.fromLTWH(body.left, body.top - header, width, body.height + header);
}

class CanvasAuthorBadge extends StatelessWidget {
  const CanvasAuthorBadge({super.key, required this.attribution, this.size = 15});

  final CanvasAttribution attribution;
  final double size;

  static String _line(String verb, AuthorStamp stamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(stamp.at);
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${two(time.day)}.${two(time.month)}.${time.year}.';
    return '$verb by ${stamp.initials} on $date at ${two(time.hour)}:${two(time.minute)}.';
  }

  @override
  Widget build(BuildContext context) {
    final latest = attribution.latest;
    if (latest == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Show author and dates',
      child: Material(
        color: colors.primaryContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Activity'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attribution.created case final stamp?) Text(_line('Created', stamp)),
                  if (attribution.edited case final stamp?) Text(_line('Edited', stamp)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: Text(latest.initials,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(fontSize: size * .5, fontWeight: FontWeight.w700,
                    color: colors.onPrimaryContainer)),
            ),
          ),
        ),
      ),
    );
  }
}

class InkObjectFrame extends StatelessWidget {
  const InkObjectFrame({super.key, required this.app, required this.block,
    required this.connected});

  final AppState app;
  final Block block;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final selected = app.selectedIds.contains(block.id);
    final showHeader = selected && !app.inkToolInHand;
    final outline = connected || block.outlinePinned || showHeader;
    final author = block.attribution;
    final showAuthor = app.showAuthorBadges && author.latest != null;
    if (!outline && !showAuthor) return const SizedBox.shrink();
    final rect = canvasObjectFrame(app, block);
    final colors = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        children: [
          if (outline)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: showHeader ? colors.primary : colors.outline),
                  ),
                ),
              ),
            ),
          if (showAuthor || showHeader)
            Positioned(
              right: 3,
              top: 0,
              height: app.canvasHeaderSize.height,
              child: IgnorePointer(
                ignoring: app.inkToolInHand,
                child: Listener(
                  onPointerDown: (event) => app.claimedPointers.add(event.pointer),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAuthor) CanvasAuthorBadge(attribution: author,
                          size: math.min(24.0, app.canvasHeaderSize.height - 1)),
                      if (showHeader)
                        Tooltip(
                          message: block.outlinePinned ? 'Unpin outline' : 'Pin outline',
                          child: InkWell(
                            onTap: () => app.toggleBlockOutline(block),
                            child: SizedBox.square(
                              dimension: 18,
                              child: Icon(block.outlinePinned
                                  ? Icons.visibility : Icons.visibility_outlined, size: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
