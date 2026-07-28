import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/onboarding_store.dart';

/// The onboarding-completion store. Overridden with a fake in tests.
final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => SharedPreferencesOnboardingStore(),
);
