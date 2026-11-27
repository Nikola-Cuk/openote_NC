import 'package:flutter/material.dart';

Future<DateTime?> pickReminderTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final first = DateUtils.dateOnly(now);
  final last = DateTime(now.year + 50, 12, 31);
  final base = initial.isBefore(now) || initial.isAfter(last)
      ? now.add(const Duration(hours: 1))
      : initial;
  final day = await showDatePicker(
    context: context, initialDate: base, firstDate: first, lastDate: last,
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context, initialTime: TimeOfDay.fromDateTime(base),
  );
  if (time == null || !context.mounted) return null;
  final result = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  if (result.isAfter(DateTime.now())) return result;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('Choose a reminder time in the future.')),
  );
  return null;
}
