import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/region/grid_site_resolver.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';

/// Resolves the corpus key on the device.
///
/// Built without grids: they are a build product of the corpus pipeline and
/// arrive with slice A4's assets. Until then the federative unit still resolves
/// from the address the app already reverse-geocodes, and the other key parts
/// are null — which §5.2 defines as valid and not fatal.
final siteResolverProvider = Provider<SiteResolver>((ref) {
  return const GridSiteResolver();
});
