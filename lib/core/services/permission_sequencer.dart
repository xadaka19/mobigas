import 'dart:async';

/// Serializes native OS permission-request dialogs (notifications,
/// location, camera, etc.) across the whole app.
///
/// WHY THIS EXISTS: Android can only resolve one
/// requestPermissions() callback at a time. When two different
/// plugins (e.g. firebase_messaging and geolocator) fire their own
/// permission requests close together, the loser doesn't just run
/// slow — its callback can be silently dropped, or on some OEM
/// builds (MIUI/One UI) its dialog never appears on screen at all.
/// The previous fix (a fixed millisecond delay between the two call
/// sites) only reduces the odds of a collision; it doesn't rule one
/// out, because the actual fire time on either side depends on
/// variable work (auth resolution, Firebase init) that a constant
/// delay can't account for.
///
/// Every native permission request in the app should go through
/// `PermissionSequencer.run(...)` instead of being called directly.
/// Requests queued this way are guaranteed to run one at a time, in
/// the order they were queued — so whichever fires first (splash's
/// location request, or notification init's permission request)
/// always gets its dialog, and the second always waits for the first
/// to actually finish before it ever asks.
class PermissionSequencer {
  static Future<void> _chain = Future<void>.value();

  /// Queues [request] to run only after every previously-queued
  /// permission request has finished. [maxWait] bounds how long this
  /// request will wait its turn — if something ahead of it in the
  /// chain never completes, this still fires after [maxWait] rather
  /// than being blocked forever, and a stuck request likewise can't
  /// hang everything queued behind it for more than [maxWait].
  ///
  /// Returns the result of [request], or null if [request] itself
  /// throws (errors are swallowed the same way the original
  /// individual call sites already did — a denied/failed permission
  /// request must never block app navigation).
  static Future<T?> run<T>(
    Future<T> Function() request, {
    Duration maxWait = const Duration(seconds: 6),
  }) {
    final previous = _chain;
    final gate = Completer<void>();
    _chain = gate.future;

    return previous
        .timeout(maxWait, onTimeout: () {})
        .catchError((_) {})
        .then((_) async {
      try {
        return await request();
      } catch (_) {
        return null;
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    });
  }
}
