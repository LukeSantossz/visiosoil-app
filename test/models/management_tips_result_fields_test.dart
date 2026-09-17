// The nine fields SPEC 0068 adds to the result, and the compatibility rule that
// forces every one of them to be optional.
//
// The rule is not a wire concern. `management_tips` stores the serialised
// payload and reads it back through the *same* `fromJson`, so a row cached
// before this change is parsed by the new reader. A required new field would
// make every existing row fail to parse, and the Details section has an error
// branch — the user would simply lose the offline tips they had, quietly.
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';

void main() {
  /// Exactly what today's `toJson` writes, frozen as a literal rather than
  /// produced by the current code: a payload built by the new writer would
  /// carry the new fields and could not prove anything about an old row.
  Map<String, dynamic> preChangePayload() => {
        'status': 'grounded',
        'tips': [
          {
            'text': 'Mantenha cobertura vegetal.',
            'citations': [0],
          },
        ],
        'sources': [
          {
            'title': 'Manejo de solos argilosos',
            'url': 'https://example.org/argila',
            'publisher': 'Extensão Rural',
            'date': '2025-03-01',
          },
        ],
        'disclaimer': 'Orientação consultiva; valide com análise local.',
        'model': 'corpus:2026.09.1',
        'retrievedAt': '2026-06-23T12:00:00.000Z',
      };

  group('cache compatibility', () {
    test('absent_fields_parse_to_documented_defaults', () {
      final restored = ManagementTipsResult.fromJson(preChangePayload());

      expect(restored.corpusVersion, isNull);
      expect(restored.limitations, isEmpty);
      expect(restored.alerts, isEmpty);
      expect(restored.followUpQuestions, isEmpty);
      expect(restored.coverage, isNull);
      expect(restored.tips.single.category, isNull);
      expect(restored.tips.single.evidenceStrength, isNull);
      expect(restored.sources.single.accessedAt, isNull);
      expect(restored.sources.single.tier, isNull);
    });

    test('pre_change_payload_keeps_the_fields_it_had', () {
      final restored = ManagementTipsResult.fromJson(preChangePayload());

      expect(restored.status, ManagementTipsStatus.grounded);
      expect(restored.tips.single.text, 'Mantenha cobertura vegetal.');
      expect(restored.tips.single.citations, [0]);
      expect(restored.sources.single.publisher, 'Extensão Rural');
      expect(restored.model, 'corpus:2026.09.1');
      expect(restored.retrievedAt, DateTime.utc(2026, 6, 23, 12));
    });
  });

  group('defensive enumerations', () {
    test('unknown_tip_category_does_not_throw', () {
      final payload = preChangePayload();
      (payload['tips'] as List).first['category'] = 'irrigation_schedule';

      final restored = ManagementTipsResult.fromJson(payload);

      expect(restored.tips.single.category, isNull);
    });

    test('unknown_evidence_strength_does_not_throw', () {
      final payload = preChangePayload();
      (payload['tips'] as List).first['evidenceStrength'] = 'overwhelming';

      final restored = ManagementTipsResult.fromJson(payload);

      expect(restored.tips.single.evidenceStrength, isNull);
    });

    test('known_enum_members_parse', () {
      final payload = preChangePayload();
      (payload['tips'] as List).first['category'] = 'water';
      (payload['tips'] as List).first['evidenceStrength'] = 'moderate';

      final restored = ManagementTipsResult.fromJson(payload);

      expect(restored.tips.single.category, TipCategory.water);
      expect(restored.tips.single.evidenceStrength, EvidenceStrength.moderate);
    });

    test('unknown_status_still_throws', () {
      // A category the client does not know is a corpus that moved ahead of it.
      // A status it does not know is a malformed payload, and swallowing it
      // would render an unknown state as if it were a known one.
      final payload = preChangePayload()..['status'] = 'probably';

      expect(
        () => ManagementTipsResult.fromJson(payload),
        throwsArgumentError,
      );
    });

    test('insufficient_evidence_is_a_status', () {
      final payload = preChangePayload()
        ..['status'] = 'insufficient_evidence'
        ..['tips'] = <dynamic>[];

      final restored = ManagementTipsResult.fromJson(payload);

      expect(restored.status, ManagementTipsStatus.insufficientEvidence);
    });
  });

  group('completeness of what this version writes', () {
    ManagementTipsResult fullSample() => ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: const [
            ManagementTip(
              text: 'Mantenha cobertura vegetal.',
              citations: [0, 1],
              category: TipCategory.preparation,
              evidenceStrength: EvidenceStrength.strong,
            ),
          ],
          sources: const [
            TipSource(
              title: 'Manejo de solos argilosos',
              url: 'https://example.org/argila',
              publisher: 'Embrapa',
              date: '2025-03-01',
              accessedAt: '2026-09-10T00:00:00.000Z',
              tier: 1,
            ),
            TipSource(title: 'Boletim', url: 'https://example.org/bt'),
          ],
          disclaimer: 'Orientação consultiva.',
          model: 'corpus:2026.09.1',
          retrievedAt: DateTime.utc(2026, 9, 10),
          corpusVersion: '2026.09.1',
          limitations: const ['Não substitui análise laboratorial.'],
          alerts: const ['Corpus com mais de seis meses.'],
          followUpQuestions: const ['Qual o histórico de calagem?'],
          coverage: const TipsCoverage(
            clayActivity: 'tb_oxidic',
            substanceIsGeneric: false,
            unit: 'BR-SP',
            unitLayerPresent: true,
            biome: 'cerrado',
            landUse: 'pasture',
            landUseLayerPresent: true,
          ),
        );

    test('to_json_writes_every_field', () {
      final json = fullSample().toJson();

      for (final key in const [
        'status',
        'tips',
        'sources',
        'disclaimer',
        'model',
        'retrievedAt',
        'corpusVersion',
        'limitations',
        'alerts',
        'followUpQuestions',
        'coverage',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '$key is not written');
      }
      final tip = (json['tips'] as List).single as Map<String, dynamic>;
      expect(tip.containsKey('category'), isTrue);
      expect(tip.containsKey('evidenceStrength'), isTrue);
      final source = (json['sources'] as List).first as Map<String, dynamic>;
      expect(source.containsKey('accessedAt'), isTrue);
      expect(source.containsKey('tier'), isTrue);
    });

    test('full_result_round_trips', () {
      final original = fullSample();
      final restored = ManagementTipsResult.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.coverage!.unit, 'BR-SP');
      expect(restored.tips.single.category, TipCategory.preparation);
    });
  });
}
