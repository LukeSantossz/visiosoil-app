import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/ambient_light_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel('com.visiosoil.app/ambient_light');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockStreamHandler(channel, null));

  Future<({List<double> values, List<Object> errors})> collect() async {
    final values = <double>[];
    final errors = <Object>[];
    final done = const PlatformAmbientLightSource().lux.listen(
      values.add,
      onError: errors.add,
    );
    await pumpEventQueue();
    await done.cancel();
    return (values: values, errors: errors);
  }

  test('platform_light_streams_the_sensor_lux', () async {
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (arguments, events) => events.success(1480.0),
      ),
    );
    final read = await collect();
    expect(read.values, [1480.0]);
    expect(read.errors, isEmpty);
  });

  group('platform_light_stays_quiet_on_an_error', () {
    test('an error event', () async {
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (arguments, events) => events.error(code: 'SENSOR'),
        ),
      );
      final read = await collect();
      expect(read.values, isEmpty);
      expect(read.errors, isEmpty);
    });

    test('a missing plugin', () async {
      final read = await collect();
      expect(read.values, isEmpty);
      expect(read.errors, isEmpty);
    });
  });
}
