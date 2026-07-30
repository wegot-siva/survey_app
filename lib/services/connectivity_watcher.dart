import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Turns the raw connectivity stream into the one event the sync layer
/// actually cares about: the device just regained a connection.
///
/// Deliberately narrower than "connectivity changed". The underlying stream
/// also fires when an already-online device swaps transports (Wi-Fi to
/// mobile as someone walks out of range, or onto a VPN), and syncing on
/// those is pointless churn — nothing became reachable that wasn't already.
/// Only an offline → online transition is reported.
///
/// Event-driven, never polled: [Connectivity.onConnectivityChanged] is a
/// platform callback stream, and it already applies `.distinct()`, so an
/// unchanged state never re-emits.
class ConnectivityWatcher {
  ConnectivityWatcher({Stream<List<ConnectivityResult>>? stream})
      : _stream = stream ?? Connectivity().onConnectivityChanged;

  final Stream<List<ConnectivityResult>> _stream;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Whether the last observed state had no usable connection. Starts false
  /// so an app that launches already-online doesn't treat its very first
  /// event as a "restore" — launch already syncs on its own, and firing here
  /// too would just duplicate it. An app that launches offline sees `[none]`
  /// first, which sets this, so the genuine restore still fires.
  bool _wasOffline = false;

  /// True once [start] has run and until [dispose] — exposed for tests.
  bool get isListening => _subscription != null;

  /// Whether [results] represents a usable connection. An empty list is
  /// treated as offline: some platforms report that instead of `[none]`.
  static bool isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      results.any((r) => r != ConnectivityResult.none);

  /// Begins listening. [onRestored] fires once per offline → online
  /// transition. It is NOT debounced here — the sync layer's own debounce
  /// handles a flapping connection, so this stays a pure signal and the
  /// throttling policy lives in one place.
  void start(void Function() onRestored) {
    _subscription ??= _stream.listen((results) {
      final online = isOnline(results);
      final restored = online && _wasOffline;
      _wasOffline = !online;
      if (restored) onRestored();
    });
  }

  Future<void> dispose() async {
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
  }
}
