import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/site_key.dart';

/// One reviewed cell of the corpus: the guidance for one key of one layer.
///
/// [tips] cite by index into **this cell's own** [sources]. Re-indexing them
/// onto the composed source list is [CorpusComposer]'s job, and the single
/// subtle part of the rule.
class CorpusCell {
  const CorpusCell({
    required this.status,
    required this.tips,
    required this.sources,
    this.limitations = const [],
    this.alerts = const [],
    this.followUpQuestions = const [],
    this.disclaimer,
  });

  final ManagementTipsStatus status;
  final List<ManagementTip> tips;
  final List<TipSource> sources;
  final List<String> limitations;
  final List<String> alerts;
  final List<String> followUpQuestions;

  /// Only the substance layer carries one; it becomes the composed result's.
  final String? disclaimer;

  /// Reads a cell, refusing a citation that does not resolve within the cell.
  ///
  /// §12.1 makes an unresolvable citation a build failure, so composition may
  /// assume resolvable input and is not a validation step. That assumption is
  /// checked once here, at the boundary, because a corpus that reaches a device
  /// with a bad citation must say so rather than render a footnote marker that
  /// points nowhere.
  factory CorpusCell.fromJson(Map<String, dynamic> json, {required String key}) {
    final sources = ((json['sources'] as List<dynamic>?) ?? const [])
        .map((e) => TipSource.fromJson(e as Map<String, dynamic>))
        .toList();
    final tips = ((json['tips'] as List<dynamic>?) ?? const [])
        .map((e) => ManagementTip.fromJson(e as Map<String, dynamic>))
        .toList();
    for (final tip in tips) {
      for (final citation in tip.citations) {
        if (citation < 0 || citation >= sources.length) {
          throw FormatException(
            'corpus cell "$key" has a citation $citation with only '
            '${sources.length} source(s)',
          );
        }
      }
    }
    return CorpusCell(
      status: ManagementTipsStatus.fromWire(
          (json['status'] as String?) ?? 'grounded'),
      tips: tips,
      sources: sources,
      limitations: _strings(json['limitations']),
      alerts: _strings(json['alerts']),
      followUpQuestions: _strings(json['followUpQuestions']),
      disclaimer: json['disclaimer'] as String?,
    );
  }

  static List<String> _strings(dynamic value) => value == null
      ? const []
      : (value as List<dynamic>).map((e) => e as String).toList();
}

/// The reviewed artifact the app holds and composes from.
///
/// Three layers, keyed as §5.1 fixes them: substance by
/// `"<textureClass>|<clayActivity>"`, land use by its wire name, and the
/// institutional layer by federative unit and by biome.
class Corpus {
  const Corpus({
    required this.corpusVersion,
    required this.disclaimer,
    required this.fetchedAt,
    required this.substance,
    this.landUse = const {},
    this.unit = const {},
    this.biome = const {},
    this.clayActivityDefaultByBiome = const {},
  });

  final String corpusVersion;

  /// Used when no substance cell answered, so the composed result always
  /// carries a non-empty disclaimer.
  final String disclaimer;

  /// When the corpus was fetched — **not** when composition ran. It becomes the
  /// result's `retrievedAt`, which is what keeps the composer pure.
  final DateTime fetchedAt;

  final Map<String, CorpusCell> substance;
  final Map<String, CorpusCell> landUse;
  final Map<String, CorpusCell> unit;
  final Map<String, CorpusCell> biome;

  /// Which clay-activity family to assume when the grid could not resolve one.
  /// Data rather than code, so refining it is a corpus release.
  final Map<String, ClayActivity> clayActivityDefaultByBiome;

  factory Corpus.fromJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    Map<String, CorpusCell> layer(String name) {
      final raw = json[name] as Map<String, dynamic>?;
      if (raw == null) return const {};
      return {
        for (final entry in raw.entries)
          entry.key: CorpusCell.fromJson(
            entry.value as Map<String, dynamic>,
            key: '$name/${entry.key}',
          ),
      };
    }

    final disclaimer = json['disclaimer'] as String;
    if (disclaimer.trim().isEmpty) {
      // The result contract says the disclaimer is never empty, and this value
      // is what a composition falls back to when no substance cell carries one.
      // An empty value here would produce a contract-violating result silently,
      // so it is refused where it enters rather than where it shows.
      throw const FormatException('corpus disclaimer is empty; every composed '
          'result must carry one');
    }

    final defaults = json['clayActivityDefaultByBiome'] as Map<String, dynamic>?;
    return Corpus(
      corpusVersion: json['corpusVersion'] as String,
      disclaimer: disclaimer,
      fetchedAt: fetchedAt.toUtc(),
      substance: layer('substance'),
      landUse: layer('landUse'),
      unit: layer('unit'),
      biome: layer('biome'),
      clayActivityDefaultByBiome: defaults == null
          ? const {}
          : {
              for (final entry in defaults.entries)
                entry.key: ?ClayActivity.fromWire(entry.value as String?),
            },
    );
  }

  /// The substance key for a class and a clay-activity family.
  static String substanceKey(String textureClass, ClayActivity activity) =>
      '$textureClass|${activity.wireName}';
}

/// Turns a key and a corpus into a [ManagementTipsResult], with no I/O.
///
/// Pure by design: no async, no assets, no clock. `retrievedAt` comes from the
/// corpus rather than from `DateTime.now()`, which is what makes the golden
/// fixture possible and keeps the rule testable without a device
/// (`docs/architecture/research-agent.md` §19.3).
class CorpusComposer {
  const CorpusComposer();

  /// Composes the layers in the fixed order of §6.5: substance, land use, then
  /// the institutional layer — which is the federative unit followed by the
  /// biome, in that order, so a citation offset is deterministic.
  ManagementTipsResult compose({
    required Corpus corpus,
    required String textureClass,
    required SiteKey site,
    required LandUse? landUse,
  }) {
    final activity = site.clayActivity ??
        (site.biome == null
            ? null
            : corpus.clayActivityDefaultByBiome[site.biome!.wireName]);

    final substance = activity == null
        ? null
        : corpus.substance[Corpus.substanceKey(textureClass, activity)];
    final landUseCell = landUse == null ? null : corpus.landUse[landUse.wireName];
    final unitCell = site.unit == null ? null : corpus.unit[site.unit!];
    final biomeCell =
        site.biome == null ? null : corpus.biome[site.biome!.wireName];

    final layers = <CorpusCell>[?substance, ?landUseCell, ?unitCell, ?biomeCell];

    final tips = <ManagementTip>[];
    final sources = <TipSource>[];
    final limitations = <String>[];
    final alerts = <String>[];
    final followUpQuestions = <String>[];

    for (final layer in layers) {
      // The offset this layer's sources begin at, captured before they are
      // appended: every citation in it shifts by exactly this much.
      final offset = sources.length;
      sources.addAll(layer.sources);
      for (final tip in layer.tips) {
        tips.add(ManagementTip(
          text: tip.text,
          citations: [for (final i in tip.citations) i + offset],
          category: tip.category,
          evidenceStrength: tip.evidenceStrength,
        ));
      }
      _addMissing(limitations, layer.limitations);
      _addMissing(alerts, layer.alerts);
      _addMissing(followUpQuestions, layer.followUpQuestions);
    }

    return ManagementTipsResult(
      status: _statusOf(substance: substance, anyTips: tips.isNotEmpty),
      tips: tips,
      sources: sources,
      disclaimer: _nonEmpty(substance?.disclaimer) ?? corpus.disclaimer,
      model: 'corpus:${corpus.corpusVersion}',
      retrievedAt: corpus.fetchedAt,
      corpusVersion: corpus.corpusVersion,
      limitations: limitations,
      alerts: alerts,
      followUpQuestions: followUpQuestions,
      coverage: TipsCoverage(
        clayActivity: site.clayActivity?.wireName,
        substanceIsGeneric: site.substanceIsGeneric,
        unit: site.unit,
        unitLayerPresent: unitCell != null,
        biome: site.biome?.wireName,
        landUse: landUse?.wireName,
        landUseLayerPresent: landUseCell != null,
      ),
    );
  }

  /// §6.5 gives three rules that overlap, and this is the precedence between
  /// them: **an explicit substance abstention outranks overlays that
  /// contributed.** The overlays say which agency to call and what land use
  /// changes; neither is guidance about the soil, so composing them into a
  /// `grounded` result would assert something the substance layer refused to.
  static ManagementTipsStatus _statusOf({
    required CorpusCell? substance,
    required bool anyTips,
  }) {
    if (substance?.status == ManagementTipsStatus.abstained) {
      return ManagementTipsStatus.abstained;
    }
    return anyTips
        ? ManagementTipsStatus.grounded
        : ManagementTipsStatus.insufficientEvidence;
  }

  /// Concatenates, de-duplicating by exact string and keeping first occurrence.
  static void _addMissing(List<String> into, List<String> values) {
    for (final value in values) {
      if (!into.contains(value)) into.add(value);
    }
  }

  static String? _nonEmpty(String? value) =>
      (value != null && value.trim().isNotEmpty) ? value : null;
}
