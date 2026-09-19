/// The key a corpus lookup is performed against.
///
/// It names a **site**, not a region: after the 2026-09-11 re-key the value
/// carries the clay-activity family that keys the substance layer, the
/// federative unit that keys the institutional overlay, and the biome that
/// selects the Embrapa unit. Calling it a region would describe the smallest of
/// the three (`docs/architecture/research-agent.md` §19.3).
///
/// Every part but [country] may be null and none of them is fatal: a null
/// [clayActivity] falls back to a generic substance cell, a null [unit] drops
/// the institutional overlay, and §6 defines each as a valid request.
library;

/// Clay-activity family — what actually decides whether a texture class means
/// low CEC and high phosphorus adsorption or high CEC and shrink-swell. The
/// 2026-09-11 agronomic review found biome to be a lossy proxy for it, which is
/// why the substance layer is keyed here and biome moved to the institutional
/// layer (ADR 0022).
enum ClayActivity {
  /// Deeply weathered, low-activity clay — CEC of the clay fraction below
  /// 27 cmolc/kg (SiBCS Tb).
  tbOxidic('tb_oxidic'),

  /// Between the two.
  intermediate('intermediate'),

  /// Less weathered, high-activity clay (SiBCS Ta).
  taLessWeathered('ta_less_weathered');

  const ClayActivity(this.wireName);

  final String wireName;

  /// Parses [wireName], returning null for an unrecognised value.
  static ClayActivity? fromWire(String? value) {
    if (value == null) return null;
    for (final activity in values) {
      if (activity.wireName == value) return activity;
    }
    return null;
  }
}

/// The six IBGE biomes. Kept in the model and moved to the institutional layer,
/// because Embrapa's decentralised units are themselves biome-shaped.
enum Biome {
  amazonia('amazonia'),
  cerrado('cerrado'),
  mataAtlantica('mata_atlantica'),
  caatinga('caatinga'),
  pampa('pampa'),
  pantanal('pantanal');

  const Biome(this.wireName);

  final String wireName;

  /// Parses [wireName], returning null for an unrecognised value.
  static Biome? fromWire(String? value) {
    if (value == null) return null;
    for (final biome in values) {
      if (biome.wireName == value) return biome;
    }
    return null;
  }
}

/// What a coordinate and an address resolve to, on the device.
///
/// Always a value: [SiteKey.unresolved] is what a null or out-of-coverage
/// coordinate yields, so a caller cannot forget the case the way a nullable key
/// would let it.
class SiteKey {
  const SiteKey({
    this.country = brazil,
    this.clayActivity,
    this.unit,
    this.biome,
  });

  /// Nothing resolved — a record saved without location, or a coordinate
  /// outside coverage. Not an error: §6 defines it as a valid request.
  const SiteKey.unresolved()
      : country = brazil,
        clayActivity = null,
        unit = null,
        biome = null;

  /// The only country the corpus covers. A coordinate outside Brazil is a
  /// corpus miss and is told so plainly (§5.1).
  static const String brazil = 'BR';

  final String country;

  /// Keys the substance layer. Null means the grid could not resolve it and a
  /// generic cell answers instead.
  final ClayActivity? clayActivity;

  /// ISO 3166-2:BR code, from the address the app already reverse-geocodes.
  /// Null drops the institutional overlay.
  final String? unit;

  /// Selects the regional Embrapa unit. Null drops that part of the overlay.
  final Biome? biome;

  /// True when no clay-activity family resolved, so the substance layer answers
  /// generically. Reported to the user through `TipsCoverage`.
  bool get substanceIsGeneric => clayActivity == null;

  @override
  bool operator ==(Object other) =>
      other is SiteKey &&
      other.country == country &&
      other.clayActivity == clayActivity &&
      other.unit == unit &&
      other.biome == biome;

  @override
  int get hashCode => Object.hash(country, clayActivity, unit, biome);

  @override
  String toString() => 'SiteKey($country, ${clayActivity?.wireName}, '
      '$unit, ${biome?.wireName})';
}
