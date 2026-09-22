import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/region/corpus_grid_assets.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';

/// Resolves the corpus key on the device, from the grids bundled with the app.
///
/// The grids are read from the bundle on the resolver's first call and cached
/// for the process, so this provider stays synchronous: making it a
/// `FutureProvider` would push an `AsyncValue` through the controller and into
/// the result surface, which belongs to another terminal, for an asset read that
/// happens once.
///
/// A grid the bundle does not carry leaves its key part null, which §5.2 defines
/// as valid and not fatal — the federative unit still resolves from the address
/// the app already reverse-geocodes.
final siteResolverProvider = Provider<SiteResolver>((ref) {
  return AssetGridSiteResolver();
});
