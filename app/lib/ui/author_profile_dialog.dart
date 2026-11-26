import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';

const authorProfileTitle = 'Author profile';

Future<void> showAuthorProfile(BuildContext context, AppState app) async {
  final profile = await showDialog<String>(
    context: context,
    builder: (_) => _AuthorProfileDialog(app: app),
  );
  if (profile != null) app.setAuthorProfile(profile);
}

class _AuthorProfileDialog extends StatefulWidget {
  const _AuthorProfileDialog({required this.app});

  final AppState app;

  @override
  State<_AuthorProfileDialog> createState() => _AuthorProfileDialogState();
}

class _AuthorProfileDialogState extends State<_AuthorProfileDialog> {
  late final _name = TextEditingController(text: widget.app.authorFullName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(authorProfileTitle),
    scrollable: true,
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'First and last name'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(L.of(context).commonCancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: const Text('Save'),
      ),
    ],
  );
}
