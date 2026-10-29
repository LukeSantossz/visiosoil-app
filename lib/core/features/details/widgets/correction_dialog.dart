import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/soil_texture_reference.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The longest label the editor accepts (SPEC 0149).
const int _maxLabelLength = 60;

/// The radio value of "Não informada". A contract class name is never empty,
/// so it cannot collide with one.
const String _notGiven = '';

/// Shows the correction dialog for [record], with its true class selected and
/// its sample label prefilled, and resolves to the chosen class (null for
/// "Não informada") and the sample as typed when "Salvar" is tapped, or null
/// on cancel or on barrier dismiss (SPEC 0149, SPEC 0220).
///
/// The sample is returned untrimmed: the repository decides how a label is
/// stored.
Future<({String? trueTextureClass, String sampleLabel})?> showCorrectionDialog(
  BuildContext context,
  SoilRecord record,
) {
  return showDialog<({String? trueTextureClass, String sampleLabel})>(
    context: context,
    builder: (_) => _CorrectionDialog(record: record),
  );
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.record});

  final SoilRecord record;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late String _trueTextureClass = widget.record.trueTextureClass ?? _notGiven;
  late final TextEditingController _sampleLabel =
      TextEditingController(text: widget.record.sampleLabel);

  @override
  void dispose() {
    _sampleLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Corrigir classificação'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<String>(
              groupValue: _trueTextureClass,
              onChanged: (value) {
                if (value != null) setState(() => _trueTextureClass = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final textureClass in SoilTextureReference.modelClasses)
                    RadioListTile<String>(
                      value: textureClass,
                      contentPadding: EdgeInsets.zero,
                      title: Text(SoilTextureReference.labelFor(textureClass)),
                    ),
                  const RadioListTile<String>(
                    value: _notGiven,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Não informada'),
                  ),
                ],
              ),
            ),
            TextField(
              controller: _sampleLabel,
              maxLength: _maxLabelLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Amostra'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((
            trueTextureClass:
                _trueTextureClass == _notGiven ? null : _trueTextureClass,
            sampleLabel: _sampleLabel.text,
          )),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
