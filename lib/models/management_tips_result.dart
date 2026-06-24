/// Domain models for the Research Agent's Management Tips ("dicas de manejo").
///
/// A [ManagementTipsResult] is the advisory, source-cited output produced for a
/// Soil Record. It is fetched from the backend proxy and cached locally so a
/// record's guidance survives offline. JSON is hand-written (house style, as in
/// `AuthSession`) so the shape stays explicit and codegen-free.
library;

/// Whether the agent produced grounded tips or abstained for lack of evidence.
enum ManagementTipsStatus { grounded, abstained }

/// A single source the tips cite. [date] is the source's own publication date
/// when available, kept as the provider-supplied string (not parsed).
class TipSource {
  const TipSource({
    required this.title,
    required this.url,
    this.publisher,
    this.date,
  });

  final String title;
  final String url;
  final String? publisher;
  final String? date;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'publisher': publisher,
        'date': date,
      };

  factory TipSource.fromJson(Map<String, dynamic> json) => TipSource(
        title: json['title'] as String,
        url: json['url'] as String,
        publisher: json['publisher'] as String?,
        date: json['date'] as String?,
      );
}

/// One advisory tip. [citations] are indices into the result's [sources].
class ManagementTip {
  const ManagementTip({required this.text, required this.citations});

  final String text;
  final List<int> citations;

  Map<String, dynamic> toJson() => {
        'text': text,
        'citations': citations,
      };

  factory ManagementTip.fromJson(Map<String, dynamic> json) => ManagementTip(
        text: json['text'] as String,
        citations:
            (json['citations'] as List<dynamic>).map((e) => e as int).toList(),
      );
}

/// The complete advisory output for a Soil Record: the tips, the sources they
/// cite, a mandatory disclaimer, the model that produced them, and when they
/// were retrieved.
class ManagementTipsResult {
  const ManagementTipsResult({
    required this.status,
    required this.tips,
    required this.sources,
    required this.disclaimer,
    required this.model,
    required this.retrievedAt,
  });

  final ManagementTipsStatus status;
  final List<ManagementTip> tips;
  final List<TipSource> sources;
  final String disclaimer;
  final String model;

  /// When the tips were retrieved, in UTC.
  final DateTime retrievedAt;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'tips': tips.map((t) => t.toJson()).toList(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'disclaimer': disclaimer,
        'model': model,
        'retrievedAt': retrievedAt.toUtc().toIso8601String(),
      };

  factory ManagementTipsResult.fromJson(Map<String, dynamic> json) =>
      ManagementTipsResult(
        status: ManagementTipsStatus.values.byName(json['status'] as String),
        tips: (json['tips'] as List<dynamic>)
            .map((e) => ManagementTip.fromJson(e as Map<String, dynamic>))
            .toList(),
        sources: (json['sources'] as List<dynamic>)
            .map((e) => TipSource.fromJson(e as Map<String, dynamic>))
            .toList(),
        disclaimer: json['disclaimer'] as String,
        model: json['model'] as String,
        retrievedAt: DateTime.parse(json['retrievedAt'] as String).toUtc(),
      );
}
