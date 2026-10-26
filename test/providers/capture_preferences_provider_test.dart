// The capture switches' stored values and their defaults (SPEC 0208).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/providers/capture_preferences_provider.dart';

void main() {
  test('capture_preferences_default_when_nothing_is_stored', () async {
    SharedPreferences.setMockInitialValues({});

    final restored = await restoreCapturePreferences();

    expect(restored.frameGuide, isTrue);
    expect(restored.saveToGallery, isFalse);
    expect(restored.recordLocation, isTrue);
  });

  test('capture_preferences_persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(frameGuideProvider.notifier).select(false);
    await container.read(saveToGalleryProvider.notifier).select(true);
    await container.read(recordLocationProvider.notifier).select(false);

    expect(container.read(frameGuideProvider), isFalse);
    expect(container.read(saveToGalleryProvider), isTrue);
    expect(container.read(recordLocationProvider), isFalse);
    final restored = await restoreCapturePreferences();
    expect(restored.frameGuide, isFalse);
    expect(restored.saveToGallery, isTrue);
    expect(restored.recordLocation, isFalse);
  });
}
