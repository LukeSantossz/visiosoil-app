import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/providers/guided_camera_provider.dart';

/// A stopwatch whose elapsed time the test sets.
class _FakeStopwatch implements Stopwatch {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  @override
  void start() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The automatic capture's window is timed by a clock that only moves
/// forward (SPEC 0167, amended 2026-10-18).
void main() {
  test('the_window_clock_only_moves_forward', () {
    var wallReads = 0;
    final start = DateTime.utc(2026, 10, 18, 12);
    // A wall clock set back an hour on every read.
    DateTime wall() => start.subtract(Duration(hours: wallReads++));
    final watch = _FakeStopwatch();
    final clock = steadyClock(now: wall, watch: watch);

    watch.value = const Duration(milliseconds: 500);
    final first = clock();
    watch.value = const Duration(milliseconds: 1200);
    final second = clock();

    expect(first, start.add(const Duration(milliseconds: 500)));
    expect(second, start.add(const Duration(milliseconds: 1200)));
    expect(second.isBefore(first), isFalse);
    expect(wallReads, 1, reason: 'the wall clock is read once, at the start');
  });

  test('the_provider_gives_one_steady_clock', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final clock = container.read(autoCaptureClockProvider);
    expect(clock == DateTime.now, isFalse,
        reason: 'the default must not be the wall clock');
    expect(identical(container.read(autoCaptureClockProvider), clock), isTrue);
  });

  test('the_default_clock_never_goes_back', () {
    final clock = steadyClock();
    var last = clock();
    for (var i = 0; i < 1000; i++) {
      final next = clock();
      expect(next.isBefore(last), isFalse);
      last = next;
    }
  });
}
