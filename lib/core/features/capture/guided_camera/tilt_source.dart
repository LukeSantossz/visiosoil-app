import 'package:sensors_plus/sensors_plus.dart';

/// One raw accelerometer reading, gravity included, in m/s².
typedef AccelerationSample = ({double x, double y, double z});

/// Where the guided camera's level reads the phone's acceleration.
abstract interface class TiltSource {
  Stream<AccelerationSample> get samples;
}

/// [TiltSource] over `sensors_plus`' raw accelerometer (SPEC 0165).
class SensorsPlusTiltSource implements TiltSource {
  @override
  Stream<AccelerationSample> get samples =>
      accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .map((event) => (x: event.x, y: event.y, z: event.z));
}
