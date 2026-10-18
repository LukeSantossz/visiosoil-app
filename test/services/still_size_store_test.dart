import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/still_size_store.dart';

void main() {
  test('a_stored_size_reads_back', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesStillSizeStore();
    expect(await store.read(), isNull);
    await store.write(const Size(3000, 4000));
    expect(await store.read(), const Size(3000, 4000));
  });

  test('an_unreadable_value_reads_as_none', () async {
    SharedPreferences.setMockInitialValues(
        {'guided_camera_still_size': 'not a size'});
    expect(await SharedPreferencesStillSizeStore().read(), isNull);
  });
}
