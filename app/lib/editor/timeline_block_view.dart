import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../model/timeline.dart';
import '../state/app_state.dart';
import '../ui/reminder_time_picker.dart';

class TimelineBlockView extends StatefulWidget {
  const TimelineBlockView({super.key, required this.block, required this.app});

  final Block block;
  final AppState app;

  @override
  State<TimelineBlockView> createState() => _TimelineBlockViewState();
}

class _TimelineBlockViewState extends State<TimelineBlockView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  AppState get app => widget.app;
  Block get block => widget.block;

  Future<void> _edit({TimelineEvent? event, bool reminder = false}) async {
    app.select(block.id);
    final existing = event == null ? null : app.timelineReminder(block, event);
    final result = await showDialog<_EventEdit>(
      context: context,
      builder: (context) => _EventDialog(
        event: event,
        reminderAt: existing != null && !existing.dismissed ? existing.at : null,
        startWithReminder: reminder,
      ),
    );
    if (!mounted || result == null) return;
    if (result.remove && event != null) {
      app.removeTimelineEvent(block, event);
      return;
    }
    final saved = result.event;
    if (saved != null) {
      app.saveTimelineEvent(block, saved, reminderAt: result.reminderAt,
          changeReminder: result.changeReminder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final events = TimelineEvent.of(block);
    final editable = app.canEditTimeline(block);
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: app.planner,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 2),
              child: Row(children: [
                Icon(Icons.timeline, size: 19, color: colors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Timeline', maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Add reminder event',
                  onPressed: editable ? () => _edit(reminder: true) : null,
                  icon: const Icon(Icons.notification_add_outlined, size: 19),
                ),
                IconButton(
                  tooltip: 'Add timeline event',
                  onPressed: editable ? () => _edit() : null,
                  icon: const Icon(Icons.add, size: 21),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Text('Add an event to start the timeline.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant)),
                    )
                  : LayoutBuilder(builder: (context, constraints) =>
                      _track(context, events, constraints, editable)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _track(BuildContext context, List<TimelineEvent> events,
      BoxConstraints constraints, bool editable) {
    final colors = Theme.of(context).colorScheme;
    const cardWidth = 136.0;
    final centers = <double>[cardWidth / 2 + 10];
    final span = math.max(1, events.last.day.difference(events.first.day).inDays);
    for (var i = 1; i < events.length; i++) {
      final gap = events[i].day.difference(events[i - 1].day).inDays;
      centers.add(centers.last + cardWidth + 10 + 190 * gap / span);
    }
    final width = math.max(constraints.maxWidth, centers.last + cardWidth / 2 + 10);
    final height = math.max(208.0, constraints.maxHeight);
    final middle = height / 2;
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: width > constraints.maxWidth,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Stack(
            alignment: Alignment.topLeft,
            children: [
              Positioned(
                left: 12, right: 12, top: middle - 1,
                child: Container(height: 3, decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .46),
                  borderRadius: BorderRadius.circular(2),
                )),
              ),
              for (var i = 0; i < events.length; i++) ...[
                Positioned(
                  left: centers[i] - .5,
                  top: i.isEven ? middle - 29 : middle,
                  child: Container(width: 1, height: 29, color: colors.outline),
                ),
                Positioned(
                  top: i.isOdd ? middle + 28 : null,
                  bottom: i.isEven ? height - middle + 28 : null,
                  left: centers[i] - cardWidth / 2,
                  width: cardWidth,
                  child: _eventLabel(context, events[i], editable),
                ),
                Positioned(
                  left: centers[i] - 15,
                  top: middle - 15,
                  child: _eventPoint(context, events[i], editable),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventPoint(BuildContext context, TimelineEvent event, bool editable) {
    final colors = Theme.of(context).colorScheme;
    final hasCanvas = app.node(event.canvasPageId) != null;
    final open = hasCanvas || editable;
    return Tooltip(
      message: hasCanvas ? 'Open canvas for ${event.title}' : 'Create canvas for ${event.title}',
      child: Material(
        color: hasCanvas ? colors.primary : colors.primaryContainer,
        shape: CircleBorder(side: BorderSide(color: colors.primary, width: 1.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: open ? () => app.openTimelineCanvas(block, event) : null,
          child: SizedBox(
            width: 30, height: 30,
            child: Icon(hasCanvas ? Icons.layers_outlined : Icons.add, size: 17,
                color: hasCanvas ? colors.onPrimary : colors.onPrimaryContainer),
          ),
        ),
      ),
    );
  }

  Widget _eventLabel(BuildContext context, TimelineEvent event, bool editable) {
    final colors = Theme.of(context).colorScheme;
    final reminder = app.timelineReminder(block, event);
    final hasReminder = reminder != null && !reminder.dismissed;
    final date = MaterialLocalizations.of(context).formatMediumDate(event.day);
    return Material(
      elevation: 1,
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: editable ? () => _edit(event: event) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(date,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant))),
              if (hasReminder)
                Icon(Icons.notifications_active_outlined, size: 13, color: colors.primary),
              if (editable) const Icon(Icons.edit_outlined, size: 12),
            ]),
            const SizedBox(height: 3),
            Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

typedef _EventEdit = ({
  TimelineEvent? event,
  DateTime? reminderAt,
  bool changeReminder,
  bool remove,
});

class _EventDialog extends StatefulWidget {
  const _EventDialog({
    required this.event, required this.reminderAt, required this.startWithReminder,
  });
  final TimelineEvent? event;
  final DateTime? reminderAt;
  final bool startWithReminder;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.event?.title);
  late DateTime _day = widget.event?.day ?? DateUtils.dateOnly(DateTime.now());
  late bool _remind = widget.startWithReminder || widget.reminderAt != null;
  late DateTime? _reminderAt =
      widget.reminderAt ?? (widget.startWithReminder ? _defaultReminder() : null);
  bool _customReminder = false;
  String? _reminderError;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime? _defaultReminder() {
    final now = DateTime.now();
    if (_day.isBefore(DateUtils.dateOnly(now))) return null;
    final at = DateTime(_day.year, _day.month, _day.day, 9);
    if (at.isAfter(now)) return at;
    final next = now.add(const Duration(minutes: 16));
    return DateTime(next.year, next.month, next.day, next.hour, next.minute);
  }

  Future<void> _pickDay() async {
    final first = DateTime(1700);
    final last = DateTime(2500, 12, 31);
    final selected = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(first) || _day.isAfter(last) ? DateTime.now() : _day,
      firstDate: first,
      lastDate: last,
    );
    if (mounted && selected != null) setState(() {
      _day = selected;
      if (widget.reminderAt == null && _remind && !_customReminder) {
        _reminderAt = _defaultReminder();
      }
    });
  }

  Future<void> _pickTime() async {
    final hint = _reminderAt ?? DateTime(_day.year, _day.month, _day.day, 9);
    final result = await pickReminderTime(context, hint);
    if (mounted && result != null) setState(() {
      _reminderAt = result;
      _customReminder = true;
      _reminderError = null;
    });
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final at = _remind ? _reminderAt : null;
    if (_remind && at == null) {
      setState(() => _reminderError = 'Choose a date and time for the reminder.');
      return;
    }
    if (at != null && at != widget.reminderAt && !at.isAfter(DateTime.now())) {
      setState(() => _reminderError = 'Choose a reminder time in the future.');
      return;
    }
    Navigator.of(context).pop<_EventEdit>((
      event: TimelineEvent(id: widget.event?.id, title: _title.text.trim(), day: _day),
      reminderAt: at, changeReminder: at != widget.reminderAt, remove: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final at = _reminderAt;
    return AlertDialog(
      title: Text(widget.event == null ? 'New timeline event' : 'Edit timeline event'),
      content: SizedBox(
        width: 370,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _title, autofocus: true,
                decoration: const InputDecoration(labelText: 'Event title'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter a title for the event.' : null,
              ),
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Timeline date'),
                subtitle: Text(l.formatFullDate(_day)),
                onTap: _pickDay,
              ),
              SwitchListTile(
                title: const Text('Remind me'),
                value: _remind,
                onChanged: (value) => setState(() {
                  _remind = value;
                  if (value) _reminderAt ??= _defaultReminder();
                  _reminderError = null;
                }),
              ),
              if (_remind)
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(at == null ? 'Set reminder date and time'
                      : '${l.formatMediumDate(at)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(at))}'),
                  subtitle: _reminderError == null ? null : Text(_reminderError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  onTap: _pickTime,
                ),
            ]),
          ),
        ),
      ),
      actions: [
        if (widget.event != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop<_EventEdit>((
              event: null, reminderAt: null, changeReminder: false, remove: true,
            )),
            child: const Text('Remove event'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
