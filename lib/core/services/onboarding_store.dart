import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the capture onboarding has been completed, so it is shown
/// only on the first launch. Behind an interface so it can be faked in tests.
abstract interface class OnboardingStore {
  /// Whether the user has already finished (or skipped) the onboarding.
  Future<bool> hasCompletedOnboarding();

  /// Records that the onboarding has been completed. Idempotent.
  Future<void> markOnboardingCompleted();
}

/// [OnboardingStore] backed by `shared_preferences` under a single boolean key.
class SharedPreferencesOnboardingStore implements OnboardingStore {
  static const _completedKey = 'onboarding_completed';

  @override
  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  @override
  Future<void> markOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
