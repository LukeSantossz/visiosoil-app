import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android application id (#267, SPEC 0088). Play never lets an id
/// change after the first upload, so the one decided before it is pinned here,
/// together with the two places that must agree with it.
///
/// Whole-line comments are stripped before asserting, so an id surviving only
/// in a comment cannot keep a guard green.
void main() {
  const id = 'com.visiosoil.app';
  const oldId = 'com.visiosoil.visiosoil_app';

  String code(String path) => File(path)
      .readAsLinesSync()
      .where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('#');
      })
      .join('\n');

  test('the_android_application_id_is_com_visiosoil_app', () {
    final gradle = code('android/app/build.gradle.kts');
    expect(gradle, contains('applicationId = "$id"'));
    expect(
      gradle,
      contains('namespace = "$id"'),
      reason:
          'the namespace resolves the manifest\'s relative .MainActivity and '
          'the generated R class, so it moves with the id',
    );
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      isNot(contains('TODO: Specify your own unique Application ID')),
      reason: 'the id is decided, so the template reminder goes',
    );
  });

  test('main_activity_is_in_the_application_package', () {
    final activity = File(
      'android/app/src/main/kotlin/com/visiosoil/app/MainActivity.kt',
    );
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsLinesSync().first, 'package $id');
    expect(
      Directory(
        'android/app/src/main/kotlin/com/visiosoil/visiosoil_app',
      ).existsSync(),
      isFalse,
      reason: 'nothing may be left under the old package path',
    );
  });

  test('the_smoke_job_launches_the_final_id', () {
    final ci = code('.github/workflows/ci.yml');
    expect(ci, contains('adb shell monkey -p $id '));
    expect(ci, contains('adb shell pidof $id '));
    for (final workflow in Directory('.github/workflows').listSync()) {
      if (workflow is File) {
        expect(
          workflow.readAsStringSync(),
          isNot(contains(oldId)),
          reason: '${workflow.path} still names the old id',
        );
      }
    }
  });
}
