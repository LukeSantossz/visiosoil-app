import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';

void main() {
  group('ManagementTipsResult JSON', () {
    ManagementTipsResult groundedSample() => ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: const [
            ManagementTip(text: 'Mantenha cobertura vegetal.', citations: [0]),
            ManagementTip(text: 'Monitore a umidade.', citations: [0, 1]),
          ],
          sources: const [
            TipSource(
              title: 'Manejo de solos argilosos',
              url: 'https://example.org/argila',
              publisher: 'Extensão Rural',
              date: '2025-03-01',
            ),
            TipSource(title: 'Boletim técnico', url: 'https://example.org/bt'),
          ],
          disclaimer: 'Orientação advisory; valide com análise local.',
          model: 'groq:llama-3.3-70b',
          retrievedAt: DateTime.utc(2026, 6, 23, 12),
        );

    test('management_tips_result_json_round_trips', () {
      final original = groundedSample();
      final restored = ManagementTipsResult.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
    });

    test('abstained_result_round_trips', () {
      final abstained = ManagementTipsResult(
        status: ManagementTipsStatus.abstained,
        tips: const [],
        sources: const [
          TipSource(title: 'Busca', url: 'https://example.org/x'),
        ],
        disclaimer: 'Evidência insuficiente para uma dica fundamentada.',
        model: 'groq:llama-3.3-70b',
        retrievedAt: DateTime.utc(2026, 6, 23, 12),
      );

      final restored = ManagementTipsResult.fromJson(abstained.toJson());

      expect(restored.status, ManagementTipsStatus.abstained);
      expect(restored.tips, isEmpty);
      expect(restored.toJson(), abstained.toJson());
    });

    test('fromJson_normalizes_retrieved_at_to_utc', () {
      final restored =
          ManagementTipsResult.fromJson(groundedSample().toJson());
      expect(restored.retrievedAt.isUtc, isTrue);
    });
  });
}
