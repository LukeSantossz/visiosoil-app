// The capture guide's seen-flag is its own key, so a user who completed the
// onboarding before the guide shipped is still shown it once (SPEC 0142).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/capture_guide_store.dart';

void main() {
  test('defaults to unseen over empty preferences', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      await SharedPreferencesCaptureGuideStore().hasSeenCaptureGuide(),
      isFalse,
    );
  });

  test('guide_flag_is_independent', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final store = SharedPreferencesCaptureGuideStore();

    expect(await store.hasSeenCaptureGuide(), isFalse);

    await store.markCaptureGuideSeen();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'onboarding_completed', 'capture_guide_seen'});
    expect(prefs.getBool('capture_guide_seen'), isTrue);
    expect(prefs.getBool('onboarding_completed'), isTrue);
    // A fresh instance over the same preferences reads the persisted flag.
    expect(
      await SharedPreferencesCaptureGuideStore().hasSeenCaptureGuide(),
      isTrue,
    );
  });
}
