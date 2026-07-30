import 'package:flutter/widgets.dart';

import '../services/sync_controller.dart';

/// Makes the signed-in account's [SyncController] reachable from anywhere
/// below it without threading it through every screen's constructor.
///
/// Sits above the app's Navigator (see main.dart), so screens pushed on top
/// of the home screen — every survey section form — can reach it too. That's
/// the whole point: sync state used to live inside `HomeScreen`'s State,
/// which put it permanently out of reach of exactly the screens that will
/// need to trigger a sync.
class SyncScope extends InheritedNotifier<SyncController> {
  /// [controller] is null while logged out — there's no account, so no sync
  /// state to expose. Nothing below reads it in that state (the login screen
  /// doesn't sync), and [watch]/[read] assert rather than silently returning
  /// null so a mistake surfaces immediately in debug rather than as a
  /// confusing null-check crash somewhere downstream.
  const SyncScope({
    super.key,
    required SyncController? controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, **subscribing** the calling context to its changes —
  /// the caller rebuilds whenever sync status changes. Use in a `build`
  /// method that renders sync state.
  ///
  /// Prefer [read] plus a tightly-scoped `ListenableBuilder` when only a
  /// small part of a large screen actually depends on the status; this
  /// rebuilds the whole calling widget.
  static SyncController watch(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<SyncScope>()
        ?.notifier;
    assert(controller != null, 'No SyncScope found above this context.');
    return controller!;
  }

  /// The controller **without** subscribing to changes — for callbacks that
  /// only want to call `requestSync`, where rebuilding the caller on every
  /// status change would be pointless churn.
  static SyncController read(BuildContext context) {
    final controller = context
        .getInheritedWidgetOfExactType<SyncScope>()
        ?.notifier;
    assert(controller != null, 'No SyncScope found above this context.');
    return controller!;
  }
}
