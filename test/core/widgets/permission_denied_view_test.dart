import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/permission_denied_view.dart';

void main() {
  testWidgets('hc_discs_are_solid: the permission disc', (tester) async {
    Future<void> pump(ThemeData theme) {
      return tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: PermissionDeniedView(
            icon: Icons.location_off,
            title: 'Localização',
            description: 'Precisamos da localização.',
          ),
        ),
      ));
    }

    Container disc() => tester.widget<Container>(find.byWidgetPredicate((widget) {
          final decoration = widget is Container ? widget.decoration : null;
          return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
        }));

    await pump(AppTheme.lightHighContrast);
    expect(
      (disc().decoration! as BoxDecoration).color,
      AppPalette.lightHighContrast.warningContainer,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.location_off)).color,
      AppPalette.lightHighContrast.onWarningContainer,
    );

    await tester.pumpWidget(const SizedBox());
    await pump(AppTheme.light);
    expect(
      (disc().decoration! as BoxDecoration).color,
      AppPalette.light.warning.withValues(alpha: 0.15),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.location_off)).color,
      AppPalette.light.warning,
    );
  });
}
