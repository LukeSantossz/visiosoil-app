import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/camera_release_queue.dart';

void main() {
  test('steps_run_in_the_order_they_were_queued', () async {
    final queue = CameraReleaseQueue();
    final ran = <String>[];
    final gate = Completer<void>();
    unawaited(queue.add(() async {
      await gate.future;
      ran.add('first');
    }));
    unawaited(queue.add(() async => ran.add('second')));
    final idle = queue.idle;

    await Future<void>.delayed(Duration.zero);
    expect(ran, isEmpty, reason: 'the second step waits for the first');
    gate.complete();
    await idle;
    expect(ran, ['first', 'second']);
  });
}
