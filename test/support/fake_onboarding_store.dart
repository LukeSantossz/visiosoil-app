import 'package:visiosoil_app/core/services/onboarding_store.dart';

/// In-memory [OnboardingStore] for tests: records how many times completion was
/// marked and lets a test seed the initial completed state.
class FakeOnboardingStore implements OnboardingStore {
  FakeOnboardingStore({this.completed = false});

  bool completed;
  int markCalls = 0;

  @override
  Future<bool> hasCompletedOnboarding() async => completed;

  @override
  Future<void> markOnboardingCompleted() async {
    markCalls++;
    completed = true;
  }
}
