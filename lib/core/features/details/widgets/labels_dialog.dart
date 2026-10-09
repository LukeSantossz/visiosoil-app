import 'package:flutter/material.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The longest label the editor accepts (SPEC 0149).
const int _maxLabelLength = 60;

/// Shows the label editor for [record], prefilled with its labels, and
/// resolves to the text as typed when "Salvar" is tapped, or null on cancel or
/// on barrier dismiss (SPEC 0149).
///
/// The text is returned untrimmed: the repository decides how a label is
/// stored.
Future<({String fieldName, String sampleLabel})?> showLabelsDialog(
  BuildContext context,
  SoilRecord record,
) {
  return showDialog<({String fieldName, String sampleLabel})>(
    context: context,
    builder: (_) => _LabelsDialog(record: record),
  );
}

class _LabelsDialog extends StatefulWidget {
  const _LabelsDialog({required this.record});

  final SoilRecord record;

  @override
  State<_LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends State<_LabelsDialog> {
  late final TextEditingController _fieldName =
      TextEditingController(text: widget.record.fieldName);
  late final TextEditingController _sampleLabel =
      TextEditingController(text: widget.record.sampleLabel);

  @override
  void dispose() {
    _fieldName.dispose();
    _sampleLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Identificação'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _fieldName,
              maxLength: _maxLabelLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Talhão'),
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
            fieldName: _fieldName.text,
            sampleLabel: _sampleLabel.text,
          )),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
