import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Export choices stay local to this sheet; optional private fields start off.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});
  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  bool _date = true;
  bool _location = false;
  bool _photos = false;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(soilRecordsStreamProvider);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Exportar análises',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (records.hasError) ...[
                const Text('Não foi possível carregar suas análises.'),
                TextButton(
                  onPressed: () => ref.invalidate(soilRecordsStreamProvider),
                  child: const Text('Tentar de novo'),
                ),
              ] else if (records.isLoading)
                const LinearProgressIndicator()
              else
                Text(
                  '${Formatters.count(records.value!.length, 'análise', 'análises')} '
                  'em uma planilha CSV.',
                ),
              const SizedBox(height: AppSpacing.lg),
              const CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Classe e confiança'),
                value: true,
                onChanged: null,
              ),
              for (final option in [
                ('Data e hora', _date, (bool value) => _date = value),
                (
                  'Localização aproximada',
                  _location,
                  (bool value) => _location = value,
                ),
                (
                  'Incluir fotos (arquivo .zip)',
                  _photos,
                  (bool value) => _photos = value,
                ),
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(option.$1),
                  value: option.$2,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => option.$3(value!)),
                ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              const SizedBox(height: AppSpacing.lg),
              VisioButton(
                label: 'Exportar',
                icon: Icons.file_download_outlined,
                expanded: true,
                isLoading: _busy,
                loadingLabel: 'Exportando…',
                onPressed:
                    records.hasError ||
                        records.isLoading ||
                        (records.value?.isEmpty ?? true)
                    ? null
                    : () async {
                        final share = ref.read(shareServiceProvider);
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        try {
                          await share.shareExport(
                            records.value!,
                            includeDate: _date,
                            includeLocation: _location,
                            includePhotos: _photos,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        } on Exception {
                          if (mounted) {
                            setState(
                              () => _error =
                                  'Não foi possível exportar as análises. Tente de novo.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
