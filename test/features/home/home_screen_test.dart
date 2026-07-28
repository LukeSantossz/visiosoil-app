import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/home/home_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Home surfaces a failure of the shared records stream with an inline
/// error+retry, while keeping the hero and the primary capture action visible
/// (#9). Both home providers derive from `soilRecordsStreamProvider`, so the
/// stream is the single seam these tests override.
SoilRecord _record() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

Widget _homeUnderTest(Stream<List<SoilRecord>> Function() streamFactory) {
  return ProviderScope(
    overrides: [
      soilRecordsStreamProvider.overrideWith((ref) => streamFactory()),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  testWidgets('home shows error and retry when the records stream fails',
      (tester) async {
    await tester.pumpWidget(
      _homeUnderTest(() => Stream.error(Exception('boom'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar seus dados.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('home keeps the primary action and hides the stats on error',
      (tester) async {
    await tester.pumpWidget(
      _homeUnderTest(() => Stream.error(Exception('boom'))),
    );
    await tester.pumpAndSettle();

    // The capture CTA stays available; the stats placeholder region is gone.
    expect(find.text('Nova análise'), findsOneWidget);
    expect(find.text('Análises'), findsNothing);
  });

  testWidgets('home retry re-subscribes and renders the data', (tester) async {
    var call = 0;
    await tester.pumpWidget(_homeUnderTest(() {
      call++;
      return call == 1
          ? Stream.error(Exception('boom'))
          : Stream.value([_record()]);
    }));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar seus dados.'), findsNothing);
    expect(find.text('Análises'), findsOneWidget);
  });
}
