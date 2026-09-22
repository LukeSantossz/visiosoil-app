import 'package:visiosoil_app/core/services/region/grid_site_resolver.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';
import 'package:visiosoil_app/core/services/research/asset_corpus_store.dart';
import 'package:visiosoil_app/models/site_key.dart';

/// Builds a [GridSiteResolver] from the grids bundled with the app.
///
/// Kept beside the resolver rather than inside it: [GridSiteResolver] takes
/// parsed grids and has no I/O, which is what lets it be tested from bytes a
/// test wrote. This is where the bytes come from.
///
/// The same two-absences rule as [AssetCorpusStore] applies. A grid the bundle
/// does not carry leaves its key part null, which §5.2 defines as valid and not
/// fatal — the substance layer answers generically and the response says so. A
/// grid that **is** present and fails the format check is a build defect and
/// throws with the asset named, because a grid silently read as absent would
/// downgrade every answer in the country without anyone noticing.
abstract final class CorpusGridAssets {
  static const String clayActivityKey = 'assets/corpus/clay-activity-grid.bin';
  static const String biomeKey = 'assets/corpus/biome-grid.bin';

  /// Loads both grids and returns a resolver over whichever are present.
  static Future<GridSiteResolver> resolver({AssetLoader? loadAsset}) async {
    final load = loadAsset ?? loadAssetFromRootBundle;
    return GridSiteResolver(
      clayActivityGrid: await _grid(clayActivityKey, load),
      biomeGrid: await _grid(biomeKey, load),
    );
  }

  static Future<PackedGrid?> _grid(String key, AssetLoader load) async {
    final bytes = await load(key);
    if (bytes == null) return null;
    try {
      return PackedGrid.parse(bytes);
    } on FormatException catch (error) {
      throw FormatException('$key is not a valid packed grid: ${error.message}');
    }
  }
}

/// A [SiteResolver] that reads its grids from the bundle on first use.
///
/// It exists so the provider graph stays synchronous. Making the resolver
/// provider a `FutureProvider` would push an `AsyncValue` into the controller
/// and from there into the result surface, which belongs to another terminal —
/// for an asset read that takes microseconds and happens once.
class AssetGridSiteResolver implements SiteResolver {
  AssetGridSiteResolver({AssetLoader? loadAsset}) : this._(loadAsset);

  AssetGridSiteResolver._(this._loadAsset);

  final AssetLoader? _loadAsset;

  Future<GridSiteResolver>? _pending;

  @override
  Future<SiteKey> resolve({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    final resolver =
        await (_pending ??= CorpusGridAssets.resolver(loadAsset: _loadAsset));
    return resolver.resolve(
      latitude: latitude,
      longitude: longitude,
      address: address,
    );
  }
}
