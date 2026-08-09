import 'package:flutter/material.dart';

/// Shown in place of a screen's content when its first read failed.
///
/// These screens read local SQLite, so a failure here is rare — but it used
/// to be a dead end: `_load()` had no `catch`, so a thrown read left
/// `_loading` stuck at true and the user staring at a spinner forever, with
/// nothing to read and nothing to tap. Offering the retry matters more than
/// usual in this app, because the same engineer is often standing in a plant
/// room with no way to ask anyone what went wrong.
///
/// Only used for a *first* load. Once a screen has content, a failed
/// refresh keeps what's on screen and reports itself in a SnackBar instead —
/// replacing readable data with an error page would lose work the user can
/// still see and act on.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.onRetry, this.details});

  final VoidCallback onRetry;

  /// The underlying error, shown verbatim under the plain-language line.
  /// Kept visible rather than hidden behind a "details" toggle: it's the
  /// only thing a user can quote back when reporting the problem.
  final Object? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              "Couldn't open this section.",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing has been lost — your saved work is still on this '
              'device. Try again, and if it keeps failing, close and reopen '
              'the app.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 12),
              Text(
                '$details',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
