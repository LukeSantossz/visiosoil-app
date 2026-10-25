import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final initialLargeTextProvider = Provider<bool>((ref) => false);
final largeTextProvider = NotifierProvider<TextSizeController, bool>(
  TextSizeController.new,
);

/// Adds the approved 1.15 multiplier to the platform's accessibility scale.
class TextSizeController extends Notifier<bool> {
  static const preferenceKey = 'appearance.largeText';
  @override
  bool build() => ref.read(initialLargeTextProvider);

  Future<void> select(bool large) async {
    state = large;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, large);
  }
}
