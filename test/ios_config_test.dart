import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS Google Sign-In configuration in `ios/Runner/Info.plist` (#66).
///
/// `GIDClientID` and the reversed-client-id URL scheme are what let the consent
/// flow redirect back into the app on iOS. The values are public redirect
/// identifiers, not secrets, so asserting them verbatim guards against typos and
/// accidental edits. If the OAuth client is ever rotated, update the plist and
/// these constants together.
void main() {
  const iosClientId =
      '510431694243-e47ime8ba2mhoa15jorp3i4s3u2g2v5g.apps.googleusercontent.com';
  const reversedClientId =
      'com.googleusercontent.apps.510431694243-e47ime8ba2mhoa15jorp3i4s3u2g2v5g';

  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  test('info_plist_declares_gidclientid', () {
    final match = RegExp(r'<key>GIDClientID</key>\s*<string>([^<]*)</string>')
        .firstMatch(plist);
    expect(
      match,
      isNotNull,
      reason: 'GIDClientID key/value is missing from ios/Runner/Info.plist',
    );
    expect(match!.group(1), iosClientId);
  });

  test('info_plist_declares_reversed_client_id_url_scheme', () {
    final schemesBlock = RegExp(
      r'<key>CFBundleURLSchemes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(
      schemesBlock,
      isNotNull,
      reason: 'CFBundleURLSchemes array is missing from ios/Runner/Info.plist',
    );
    final schemes = RegExp(r'<string>([^<]*)</string>')
        .allMatches(schemesBlock!.group(1)!)
        .map((m) => m.group(1))
        .toList();
    expect(schemes, contains(reversedClientId));
  });
}
