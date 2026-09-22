import 'package:visiosoil_app/models/site_key.dart';

/// Turns what a Soil Record already holds — a coordinate and a reverse-geocoded
/// address — into the [SiteKey] a corpus lookup is performed against.
///
/// The seam exists so the controller can be tested without a grid asset, and so
/// resolution stays on the device: a server-side resolver would reinstate the
/// coordinate egress the corpus key exists to remove
/// (`docs/architecture/research-agent.md` §5.2).
///
/// It returns a value, never null. A coordinate that resolves nothing yields
/// [SiteKey.unresolved], which §6 defines as a valid request.
abstract class SiteResolver {
  Future<SiteKey> resolve({
    double? latitude,
    double? longitude,
    String? address,
  });
}
