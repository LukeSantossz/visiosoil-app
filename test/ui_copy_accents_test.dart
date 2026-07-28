import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the pt-BR copy accentuation and the history-grid const constructors
/// (#38).
///
/// User-facing pt-BR strings must carry their accents and cedillas; a subset had
/// them stripped, producing misspelled copy inconsistent with correctly accented
/// strings elsewhere. Each entry asserts the corrected form is present and the
/// original misspelled form is gone, per file so a token cannot leak across an
/// unrelated (and correctly English) log string. The const block guards the
/// rebuild optimization on the three parameterless history-grid widgets.
void main() {
  const corrections = <String, List<(String bad, String good)>>{
    'lib/core/widgets/permission_denied_view.dart': [
      ('Abrir Configuracoes', 'Abrir Configurações'),
    ],
    'lib/core/features/settings/settings_screen.dart': [
      ('Configuracoes', 'Configurações'),
      ('Versao do app', 'Versão do app'),
      ('serao removidos', 'serão removidos'),
      ('Esta acao nao pode ser desfeita.', 'Esta ação não pode ser desfeita.'),
    ],
    'lib/core/features/capture/widgets/camera_permission_denied_view.dart': [
      ('Camera restrita', 'Câmera restrita'),
      ('Acesso a camera necessario', 'Acesso à câmera necessário'),
      ('acesso a camera esta restrito', 'acesso à câmera está restrito'),
      ('configuracoes do dispositivo', 'configurações do dispositivo'),
      (
        'precisa de acesso a camera do dispositivo',
        'precisa de acesso à câmera do dispositivo',
      ),
    ],
    'lib/core/features/details/widgets/classification_header.dart': [
      ('Confianca baixa', 'Confiança baixa'),
      ('iluminacao e enquadramento', 'iluminação e enquadramento'),
      ('Confianca moderada', 'Confiança moderada'),
      ('pode nao refletir', 'pode não refletir'),
    ],
    'lib/core/features/home/widgets/stats_grid.dart': [
      ('Analises', 'Análises'),
      ('Confianca', 'Confiança'),
    ],
    'lib/core/features/history/widgets/history_filter_bar.dart': [
      ('Buscar por endereco', 'Buscar por endereço'),
    ],
    'lib/core/features/history/widgets/history_grid.dart': [
      (
        'Nao foi possivel carregar o historico',
        'Não foi possível carregar o histórico',
      ),
    ],
    'lib/core/features/splash/splash_screen.dart': [
      ('Solicitando permissoes...', 'Solicitando permissões...'),
      ('Permissao de camera...', 'Permissão de câmera...'),
      ('Permissao de localizacao...', 'Permissão de localização...'),
      ('Analise de textura do solo', 'Análise de textura do solo'),
    ],
  };

  corrections.forEach((path, pairs) {
    group(path, () {
      final source = File(path).readAsStringSync();
      for (final (bad, good) in pairs) {
        test('"$good" is present and "$bad" is gone', () {
          expect(
            source,
            contains(good),
            reason: 'corrected copy "$good" is missing from $path',
          );
          expect(
            source.contains(bad),
            isFalse,
            reason: 'misspelled copy "$bad" still present in $path',
          );
        });
      }
    });
  });

  group('history_grid const constructors', () {
    final source =
        File('lib/core/features/history/widgets/history_grid.dart')
            .readAsStringSync();
    for (final widget in const [
      '_EmptyHistoryState',
      '_EmptySearchState',
      '_GradientOverlay',
    ]) {
      test('$widget is constructed with const', () {
        expect(
          source,
          contains('const $widget()'),
          reason:
              '$widget must have a const constructor used at its call site to '
              'avoid needless rebuilds',
        );
      });
    }
  });
}
