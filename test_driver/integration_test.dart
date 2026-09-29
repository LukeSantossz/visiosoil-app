import 'package:integration_test/integration_test_driver.dart';

/// Writes what a harness reports through `reportData` to
/// `build/integration_response_data.json` (SPEC 0086).
Future<void> main() => integrationDriver();
