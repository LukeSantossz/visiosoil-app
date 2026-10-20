import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/descriptors/soil_sample.dart';

/// Cuts the soil sample out of the photograph at a path (SPEC 0172), off the
/// UI isolate. Injectable so widget tests do not decode photographs.
final soilSampleReaderProvider = Provider<Future<Uint8List?> Function(String)>(
  (ref) => (imagePath) => Isolate.run(() => soilSampleJpeg(imagePath)),
);

/// The soil sample of the photograph at a path, or null when it has none.
/// Computed once per path for as long as the app runs.
final soilSampleProvider = FutureProvider.family<Uint8List?, String>(
  (ref, imagePath) => ref.watch(soilSampleReaderProvider)(imagePath),
);
