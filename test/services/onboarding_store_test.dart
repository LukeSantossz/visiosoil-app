import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/onboarding_store.dart';

void main() {
  test('defaults to not completed over empty preferences', () async {
    SharedPreferences.setMockInitialValues({});

    final store = SharedPreferencesOnboardingStore();

    expect(await store.hasCompletedOnboarding(), isFalse);
  });

  test('marks and persists completion across store instances', () async {
    SharedPreferences.setMockInitialValues({});

    await SharedPreferencesOnboardingStore().markOnboardingCompleted();

    // A fresh instance over the same (mock) preferences reads the persisted flag.
    expect(
      await SharedPreferencesOnboardingStore().hasCompletedOnboarding(),
      isTrue,
    );
  });
}
