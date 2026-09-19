/// Domain models for the Research Agent's Management Tips ("dicas de manejo").
///
/// A [ManagementTipsResult] is the advisory, source-cited output produced for a
/// Soil Record. Since ADR 0022 it is composed on the device from a held corpus
/// rather than fetched per record, and it is cached locally so a record's
/// guidance survives offline. JSON is hand-written (house style, as in
/// `AuthSession`) so the shape stays explicit and codegen-free.
///
/// **Every field added after the first release is optional with a documented
/// default.** `management_tips` stores the serialised payload and reads it back
/// through the *same* `fromJson`, so a row cached before a change is parsed by
/// the new reader: a required new field would make every existing row fail to
/// parse, and because the Details section has an error branch the user would
/// simply lose the offline tips they had. The local cache is the same
/// compatibility boundary as the transport.
library;

/// Whether the agent produced grounded tips, abstained for lack of evidence, or
/// found no source that met the policy at all.
///
/// [insufficientEvidence] and [abstained] are both answers rather than failures,
/// and they differ in what was available: abstention means sources were found
/// and the agent would not assert on them; insufficient evidence means the key
/// matched no cell the corpus covers.
enum ManagementTipsStatus {
  grounded('grounded'),
  abstained('abstained'),
  insufficientEvidence('insufficient_evidence');

  const ManagementTipsStatus(this.wireName);

  /// The value carried in JSON, which is not the Dart identifier for the
  /// multi-word member. The contract in `docs/architecture/research-agent.md`
  /// §7 fixes the wire spelling.
  final String wireName;

  /// Parses [wireName], throwing on an unrecognised value.
  ///
  /// Deliberately strict, unlike [TipCategory] and [EvidenceStrength]: a
  /// category this client does not know is a corpus that moved ahead of it and
  /// degrades to "no badge", but an unknown *status* has no safe reading —
  /// treating it as grounded would assert, and treating it as abstained would
  /// hide. It is a malformed payload and says so.
  static ManagementTipsStatus fromWire(String value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    throw ArgumentError.value(value, 'status', 'unknown management tips status');
  }
}

/// What a tip is about. Closed enumeration, resolved from
/// `docs/design/ux-2026/05-design-system.md` §5: the app groups by category when
/// present and renders a flat list when absent.
enum TipCategory {
  water('water'),
  crops('crops'),
  preparation('preparation'),
  other('other');

  const TipCategory(this.wireName);

  final String wireName;

  /// Parses [value], returning null for an unrecognised member so a corpus that
  /// adds one does not break a client that predates it.
  static TipCategory? fromWire(String? value) {
    if (value == null) return null;
    for (final category in values) {
      if (category.wireName == value) return category;
    }
    return null;
  }
}

/// How well the cited sources support a tip. Same defensive parsing as
/// [TipCategory], for the same reason.
enum EvidenceStrength {
  strong('strong'),
  moderate('moderate'),
  limited('limited'),
  inferred('inferred');

  const EvidenceStrength(this.wireName);

  final String wireName;

  static EvidenceStrength? fromWire(String? value) {
    if (value == null) return null;
    for (final strength in values) {
      if (strength.wireName == value) return strength;
    }
    return null;
  }
}

/// Which layers of the corpus answered, and how generically.
///
/// Reported so the surface can state absent coverage rather than hide it: a
/// generic substance layer, a missing institutional overlay and a declined land
/// use are all normal, and a record saved without location is the normal case.
class TipsCoverage {
  const TipsCoverage({
    this.clayActivity,
    required this.substanceIsGeneric,
    this.unit,
    required this.unitLayerPresent,
    this.biome,
    this.landUse,
    required this.landUseLayerPresent,
  });

  /// The clay-activity family the substance layer was keyed by, or null when the
  /// grid could not resolve it.
  final String? clayActivity;

  /// True when [clayActivity] was null and a generic cell answered instead.
  final bool substanceIsGeneric;

  final String? unit;
  final bool unitLayerPresent;
  final String? biome;
  final String? landUse;
  final bool landUseLayerPresent;

  Map<String, dynamic> toJson() => {
        'clayActivity': clayActivity,
        'substanceIsGeneric': substanceIsGeneric,
        'unit': unit,
        'unitLayerPresent': unitLayerPresent,
        'biome': biome,
        'landUse': landUse,
        'landUseLayerPresent': landUseLayerPresent,
      };

  factory TipsCoverage.fromJson(Map<String, dynamic> json) => TipsCoverage(
        clayActivity: json['clayActivity'] as String?,
        substanceIsGeneric: json['substanceIsGeneric'] as bool? ?? false,
        unit: json['unit'] as String?,
        unitLayerPresent: json['unitLayerPresent'] as bool? ?? false,
        biome: json['biome'] as String?,
        landUse: json['landUse'] as String?,
        landUseLayerPresent: json['landUseLayerPresent'] as bool? ?? false,
      );
}

/// A single source the tips cite. [date] is the source's own publication date
/// when available, kept as the provider-supplied string (not parsed).
class TipSource {
  const TipSource({
    required this.title,
    required this.url,
    this.publisher,
    this.date,
    this.accessedAt,
    this.tier,
  });

  final String title;
  final String url;
  final String? publisher;
  final String? date;

  /// When the build fetched the source. Absent means show the source's own date
  /// only. Kept as the artifact's string rather than parsed, like [date].
  final String? accessedAt;

  /// The source-policy tier of `docs/architecture/research-agent.md` §8. Absent
  /// means show no tier.
  final int? tier;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'publisher': publisher,
        'date': date,
        'accessedAt': accessedAt,
        'tier': tier,
      };

  factory TipSource.fromJson(Map<String, dynamic> json) => TipSource(
        title: json['title'] as String,
        url: json['url'] as String,
        publisher: json['publisher'] as String?,
        date: json['date'] as String?,
        accessedAt: json['accessedAt'] as String?,
        tier: json['tier'] as int?,
      );
}

/// One advisory tip. [citations] are indices into the result's [sources].
class ManagementTip {
  const ManagementTip({
    required this.text,
    required this.citations,
    this.category,
    this.evidenceStrength,
  });

  final String text;
  final List<int> citations;

  /// Absent means render flat, without grouping.
  final TipCategory? category;

  /// Absent means render no strength badge.
  final EvidenceStrength? evidenceStrength;

  Map<String, dynamic> toJson() => {
        'text': text,
        'citations': citations,
        'category': category?.wireName,
        'evidenceStrength': evidenceStrength?.wireName,
      };

  factory ManagementTip.fromJson(Map<String, dynamic> json) => ManagementTip(
        text: json['text'] as String,
        citations:
            (json['citations'] as List<dynamic>).map((e) => e as int).toList(),
        category: TipCategory.fromWire(json['category'] as String?),
        evidenceStrength:
            EvidenceStrength.fromWire(json['evidenceStrength'] as String?),
      );
}

/// The complete advisory output for a Soil Record: the tips, the sources they
/// cite, a mandatory disclaimer, what produced them, and when they were
/// retrieved.
class ManagementTipsResult {
  const ManagementTipsResult({
    required this.status,
    required this.tips,
    required this.sources,
    required this.disclaimer,
    required this.model,
    required this.retrievedAt,
    this.corpusVersion,
    this.limitations = const [],
    this.alerts = const [],
    this.followUpQuestions = const [],
    this.coverage,
  });

  final ManagementTipsStatus status;
  final List<ManagementTip> tips;
  final List<TipSource> sources;
  final String disclaimer;
  final String model;

  /// When the tips were retrieved, in UTC. For a composed result this is when
  /// the *corpus* was fetched, not when composition ran.
  final DateTime retrievedAt;

  /// The corpus release that answered. Absent means unknown, which reads as
  /// stale at the next online check.
  final String? corpusVersion;

  /// What this guidance cannot tell the reader. Absent means an empty list.
  final List<String> limitations;

  /// Conflicts, staleness and regional gaps. Absent means an empty list.
  final List<String> alerts;

  /// What would be needed to narrow the answer. Absent means an empty list.
  final List<String> followUpQuestions;

  /// Which layers answered. Absent means say nothing about regional coverage.
  final TipsCoverage? coverage;

  Map<String, dynamic> toJson() => {
        'status': status.wireName,
        'tips': tips.map((t) => t.toJson()).toList(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'disclaimer': disclaimer,
        'model': model,
        'retrievedAt': retrievedAt.toUtc().toIso8601String(),
        'corpusVersion': corpusVersion,
        'limitations': limitations,
        'alerts': alerts,
        'followUpQuestions': followUpQuestions,
        'coverage': coverage?.toJson(),
      };

  factory ManagementTipsResult.fromJson(Map<String, dynamic> json) =>
      ManagementTipsResult(
        status: ManagementTipsStatus.fromWire(json['status'] as String),
        tips: (json['tips'] as List<dynamic>)
            .map((e) => ManagementTip.fromJson(e as Map<String, dynamic>))
            .toList(),
        sources: (json['sources'] as List<dynamic>)
            .map((e) => TipSource.fromJson(e as Map<String, dynamic>))
            .toList(),
        disclaimer: json['disclaimer'] as String,
        model: json['model'] as String,
        retrievedAt: DateTime.parse(json['retrievedAt'] as String).toUtc(),
        corpusVersion: json['corpusVersion'] as String?,
        limitations: _stringList(json['limitations']),
        alerts: _stringList(json['alerts']),
        followUpQuestions: _stringList(json['followUpQuestions']),
        coverage: json['coverage'] == null
            ? null
            : TipsCoverage.fromJson(json['coverage'] as Map<String, dynamic>),
      );

  static List<String> _stringList(dynamic value) => value == null
      ? const []
      : (value as List<dynamic>).map((e) => e as String).toList();
}
