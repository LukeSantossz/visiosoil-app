import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the capture guide has been seen, so it is shown before the
/// first camera launch only (SPEC 0142). Behind an interface so it can be
/// faked in tests.
abstract interface class CaptureGuideStore {
  /// Whether the user has already confirmed the guide.
  Future<bool> hasSeenCaptureGuide();

  /// Records that the guide has been seen. Idempotent.
  Future<void> markCaptureGuideSeen();
}

/// [CaptureGuideStore] backed by `shared_preferences`, under a key of its own:
/// a user who completed the onboarding before the guide existed has still not
/// seen it.
class SharedPreferencesCaptureGuideStore implements CaptureGuideStore {
  static const _seenKey = 'capture_guide_seen';

  @override
  Future<bool> hasSeenCaptureGuide() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  @override
  Future<void> markCaptureGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }
}
