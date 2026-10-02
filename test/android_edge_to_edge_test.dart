// Android 12 to 14 draw the app edge to edge, as Android 15 does, so the
// Flutter view spans the display the system splash spans and the launch does
// not jump (#304, SPEC 0109). Android 11 and earlier, and 15+, are left alone:
// both are continuous already (SPEC 0089).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _mainActivity() {
  final activities = Directory('android/app/src/main/kotlin')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last == 'MainActivity.kt')
      .toList();
  expect(activities, hasLength(1));
  // Comments stripped, so an explanation cannot stand in for the code.
  return activities.single
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
}

/// The bodies of every block guarded by API 31 through 34.
List<String> _android12To14Blocks(String source) => RegExp(
      r'if\s*\(\s*Build\.VERSION\.SDK_INT\s+in\s+Build\.VERSION_CODES\.S\s*'
      r'\.\.\s*Build\.VERSION_CODES\.UPSIDE_DOWN_CAKE\s*\)\s*\{([^{}]*)\}',
    ).allMatches(source).map((m) => m.group(1)!).toList();

/// The body of the Kotlin function [name], up to its closing brace at four
/// spaces of indent.
String _function(String source, String name) {
  final match = RegExp(
    'fun $name\\([^)]*\\)[^{]*\\{(.*?)\\n    \\}',
    dotAll: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: '$name is not declared');
  return match!.group(1)!;
}

void main() {
  test('edge_to_edge_only_on_android_12_to_14', () {
    final source = _mainActivity();
    final onCreate = _function(source, 'onCreate');
    final guarded = _android12To14Blocks(onCreate);
    expect(guarded, hasLength(1), reason: 'onCreate needs one API 31-34 block');

    final block = guarded.single;
    expect(block, contains('setDecorFitsSystemWindows(false)'));
    expect(block, matches(RegExp(r'statusBarColor\s*=\s*Color\.TRANSPARENT')));
    expect(
      block,
      matches(RegExp(r'navigationBarColor\s*=\s*Color\.TRANSPARENT')),
    );
    expect(
      block,
      matches(RegExp(r'isStatusBarContrastEnforced\s*=\s*false')),
    );
    expect(
      block,
      matches(RegExp(r'isNavigationBarContrastEnforced\s*=\s*true')),
      reason: 'the platform keeps its scrim behind a three-button bar, as 15+',
    );

    // Nowhere else, so Android 11 and earlier keep their inset launch.
    expect(
      RegExp(r'setDecorFitsSystemWindows').allMatches(source),
      hasLength(1),
    );
  });

  test('navigation_icons_follow_the_night_mode', () {
    final source = _mainActivity();

    final match = _function(source, 'matchNavigationIconsToNightMode');
    expect(match, contains('Configuration.UI_MODE_NIGHT_MASK'));
    expect(match, contains('Configuration.UI_MODE_NIGHT_YES'));
    expect(match, contains('APPEARANCE_LIGHT_NAVIGATION_BARS'));
    expect(match, contains('setSystemBarsAppearance'));

    for (final name in ['onCreate', 'onConfigurationChanged']) {
      final blocks = _android12To14Blocks(_function(source, name));
      expect(
        blocks.where((b) => b.contains('matchNavigationIconsToNightMode(')),
        hasLength(1),
        reason: '$name must match the icons under the API 31-34 guard',
      );
    }
  });

  // MaterialApp pushes SystemUiOverlayStyle.dark or .light on every theme
  // build, and both paint the navigation bar opaque black with light icons.
  // Before each frame, the activity puts the see-through bar back, so the black
  // is never drawn (SPEC 0109).
  test('navigation_bar_stays_see_through_after_flutter_styles_it', () {
    final source = _mainActivity();

    final guarded = _android12To14Blocks(_function(source, 'onCreate'));
    expect(
      guarded.where((b) => b.contains('addOnPreDrawListener(')),
      hasLength(1),
      reason: 'onCreate must register the keeper under the API 31-34 guard',
    );
    expect(
      RegExp(r'addOnPreDrawListener').allMatches(source),
      hasLength(1),
      reason: 'nowhere else, so Android 11 and earlier keep their black bar',
    );

    final keeper = RegExp(
      r'OnPreDrawListener\s*\{(.*?)\n    \}',
      dotAll: true,
    ).firstMatch(source);
    expect(keeper, isNotNull, reason: 'the pre-draw keeper is not declared');
    final body = keeper!.group(1)!;
    expect(
      body,
      matches(RegExp(r'navigationBarColor\s*=\s*Color\.TRANSPARENT')),
    );
    expect(body, contains('matchNavigationIconsToNightMode('));
  });
}
