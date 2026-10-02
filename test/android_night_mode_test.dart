// The theme choice reaches Android's per-app night mode, which the system
// splash reads at the next cold launch (SPEC 0107). Both sides of the channel
// are asserted here, so a rename on one side cannot silently reopen #245.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the_channel_matches_on_both_sides', () {
    final source = _mainActivity();

    expect(source, contains('"${MethodChannelNightModeSync.channelName}"'));
    expect(source, contains('"${MethodChannelNightModeSync.method}"'));
    expect(
      source,
      matches(RegExp(r'"light"\s*->\s*UiModeManager\.MODE_NIGHT_NO\b')),
    );
    expect(
      source,
      matches(RegExp(r'"dark"\s*->\s*UiModeManager\.MODE_NIGHT_YES\b')),
    );
    expect(
      source,
      matches(RegExp(r'else\s*->\s*UiModeManager\.MODE_NIGHT_AUTO\b')),
      reason: '"system", and anything unknown, clears the override',
    );
    expect(
      source,
      matches(RegExp(
        r'Build\.VERSION\.SDK_INT\s*>=\s*Build\.VERSION_CODES\.S\b'
        r'[\s\S]*setApplicationNightMode',
      )),
      reason: 'setApplicationNightMode exists from API 31 only',
    );
  });

  test('the sync sends the mode by name on the channel', () async {
    const channel = MethodChannel(MethodChannelNightModeSync.channelName);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final mode in ThemeMode.values) {
      await const MethodChannelNightModeSync().apply(mode);
    }

    expect(calls.map((c) => c.method).toSet(), {
      MethodChannelNightModeSync.method,
    });
    expect(calls.map((c) => c.arguments), ['system', 'light', 'dark']);
  });

  test('a platform without the channel does not fail the choice', () async {
    // No handler is registered, so the call meets MissingPluginException.
    await expectLater(
      const MethodChannelNightModeSync().apply(ThemeMode.dark),
      completes,
    );
  });
}
