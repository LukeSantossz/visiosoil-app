import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/share_service.dart';

/// Provides the [ShareService] used to export and share records.
final shareServiceProvider = Provider<ShareService>(
  (ref) => const ShareService(),
);
