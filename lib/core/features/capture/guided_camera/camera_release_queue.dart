/// The one queue every guided camera's release and orientation reset goes
/// through, app-wide (SPEC 0165). A camera route opened while a previous one
/// is still closing waits on [idle], so two native sessions never overlap and
/// an old orientation reset never lands after a new portrait lock.
class CameraReleaseQueue {
  Future<void> _tail = Future.value();

  /// Completes once every step queued so far has run.
  Future<void> get idle => _tail;

  /// Runs [step] after every step queued before it. A step must handle its
  /// own exceptions, or every later step would fail with it.
  Future<void> add(Future<void> Function() step) {
    final previous = _tail;
    final next = () async {
      await previous;
      await step();
    }();
    _tail = next;
    return next;
  }
}
