// Recovery of a photograph lost when Android killed the app mid-capture
// (SPEC 0096), driven through the real MainScreen so the wiring is pinned too.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/services/lost_capture_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/lost_capture_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class _FakeLostCaptureService implements LostCaptureService {
  _FakeLostCaptureService(this.answer);

  final LostCapture answer;
  int calls = 0;

  @override
  Future<LostCapture> retrieve() async {
    calls++;
    return answer;
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const MainScreen()),
        GoRoute(
          path: '/capture',
          builder: (_, state) =>
              Scaffold(body: Text('CAPTURE_STUB ${state.extra}')),
        ),
      ],
    );

// The History tab in MainScreen's IndexedStack animates a spinner, so
// `pumpAndSettle` never settles; advance with fixed-duration pumps.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpHome(WidgetTester tester, LostCaptureService service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        soilRecordsStreamProvider
            .overrideWith((ref) => Stream.value(const <SoilRecord>[])),
        filteredRecordsProvider
            .overrideWith((ref) => Stream.value(const <SoilRecord>[])),
        lostCaptureServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await _settle(tester);
  await _settle(tester);
}

void main() {
  testWidgets('a_recovered_capture_opens_the_capture_screen_with_it',
      (tester) async {
    await _pumpHome(
      tester,
      _FakeLostCaptureService(const RecoveredCapture('/cache/lost.jpg')),
    );

    expect(find.text('CAPTURE_STUB /cache/lost.jpg'), findsOneWidget);

    GoRouter.of(tester.element(find.textContaining('CAPTURE_STUB'))).pop();
    await _settle(tester);
    await _settle(tester);

    expect(find.textContaining('CAPTURE_STUB'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('an_unrecoverable_capture_is_reported_on_home', (tester) async {
    await _pumpHome(
      tester,
      _FakeLostCaptureService(const UnrecoverableCapture()),
    );

    expect(find.text(AppStrings.lostCaptureUnrecoverable), findsOneWidget);
    expect(find.textContaining('CAPTURE_STUB'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('no_lost_capture_leaves_home_alone', (tester) async {
    final service = _FakeLostCaptureService(const NoLostCapture());
    await _pumpHome(tester, service);

    expect(service.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('CAPTURE_STUB'), findsNothing);
  });
}
