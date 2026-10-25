import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/profile/profile_screen.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/google_g_logo.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';

class _Auth implements AuthService {
  _Auth(this.account);
  final AuthAccount? account;
  @override
  AuthAccount? get currentAccount => account;
  @override
  Future<AuthAccount?> restoreSession() async => account;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.sun]) {
    for (final state in ['loading', 'error', 'offline', 'records']) {
      testWidgets('profile $state in ${theme.hashCode}', (tester) async {
        final semantics = tester.ensureSemantics();
        const record = SoilRecord(
          imagePath: '',
          timestamp: '2026-10-24',
          textureClass: 'Argilosa',
          confidenceScore: .8,
        );
        // Closing an unlistened single-subscription stream never completes.
        final pending = state == 'loading'
            ? StreamController<List<SoilRecord>>()
            : null;
        if (pending != null) addTearDown(pending.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authServiceProvider.overrideWithValue(_Auth(null)),
              soilRecordsStreamProvider.overrideWith(
                (ref) => switch (state) {
                  'loading' => pending!.stream,
                  'error' => Stream<List<SoilRecord>>.error(
                    Exception('database failed'),
                  ),
                  _ => Stream.value([record]),
                },
              ),
              connectivityStatusProvider.overrideWith(
                (ref) => Stream.value(
                  state == 'offline'
                      ? ConnectivityStatus.offline
                      : ConnectivityStatus.online,
                ),
              ),
            ],
            child: MaterialApp(theme: theme, home: const ProfileScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (state == 'error') {
          expect(
            find.text('Não foi possível carregar suas análises.'),
            findsOneWidget,
          );
        }
        if (state == 'offline') {
          expect(
            find.text('Sem conexão. Você pode vincular depois em Perfil.'),
            findsOneWidget,
          );
          final button = find.widgetWithText(
            OutlinedButton,
            'Continuar com o Google',
          );
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        }
        final label = find.text('Continuar com o Google');
        final logo = find.byType(GoogleGLogo);
        expect(logo, findsOneWidget);
        expect(tester.getSize(logo), const Size(18, 18));
        expect(tester.getTopLeft(label).dx - tester.getTopRight(logo).dx, 10);
        final text = tester.widget<RichText>(
          find.descendant(of: label, matching: find.byType(RichText)),
        );
        expect(text.text.style?.fontSize, 14);
        expect(text.text.style?.fontWeight, FontWeight.w500);
        expect(
          find.descendant(of: logo, matching: find.byType(ExcludeSemantics)),
          findsOneWidget,
        );
        if (state == 'records') {
          expect(
            find.text('1 análises e 1 classes guardadas neste aparelho'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      });
    }
    for (final linked in [false, true]) {
      testWidgets(
        'profile_renders_real_account_and_empty_counts_${theme.brightness}_${theme.hashCode}_$linked',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authServiceProvider.overrideWithValue(
                  _Auth(
                    linked
                        ? const AuthAccount(
                            email: 'user@test.com',
                            displayName: 'Test User',
                          )
                        : null,
                  ),
                ),
                soilRecordsStreamProvider.overrideWith(
                  (ref) => Stream.value([]),
                ),
                connectivityStatusProvider.overrideWith(
                  (ref) => Stream.value(ConnectivityStatus.online),
                ),
              ],
              child: MaterialApp(theme: theme, home: const ProfileScreen()),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(linked ? 'Test User' : 'Sem conta vinculada'),
            findsOneWidget,
          );
          expect(find.text('0/12'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Configurações').hitTestable(),
            150,
          );
          expect(find.text('Configurações'), findsOneWidget);
          await tester.ensureVisible(find.text('0/12'));
          await tester.pump();
          expect(find.bySemanticsLabel(RegExp('0 análises')), findsWidgets);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
