import 'package:flutter/material.dart';

/// A two-pixel progress strip that sits under an [AppBar] while a screen
/// re-reads data it is already showing.
///
/// These screens reload every time the user comes back from a section or
/// form (Site Hub after a survey section, the point lists after adding a
/// point). They used to flip their whole body back to a centred spinner for
/// that, which blanked content that was already on screen, threw away the
/// user's scroll position, and — in an offline-first app reading local
/// SQLite — implied a wait that isn't really happening.
///
/// The strip keeps the refresh honest but non-destructive: content stays
/// put, and the reserved height is constant whether or not it's [active],
/// so showing it never nudges the layout.
class RefreshBar extends StatelessWidget implements PreferredSizeWidget {
  const RefreshBar({super.key, required this.active});

  final bool active;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  static const double _height = 2;

  @override
  Widget build(BuildContext context) => active
      ? const LinearProgressIndicator(minHeight: _height)
      : const SizedBox(height: _height);
}
