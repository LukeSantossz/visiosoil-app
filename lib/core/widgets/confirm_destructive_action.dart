import 'package:flutter/material.dart';

/// Shows the shared destructive-action confirmation dialog and resolves to the
/// user's choice: `true` only when the confirm button is tapped, `false` on
/// cancel or on barrier dismiss.
///
/// The dialog shows [title] and [message], a plain "Cancelar" button, and a
/// confirm button labelled [confirmLabel] styled with the theme's error color.
/// Each caller keeps its own delete operation and post-action; only the dialog
/// is shared.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
