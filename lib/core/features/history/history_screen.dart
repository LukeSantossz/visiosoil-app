import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:visiosoil_app/models/soil_record.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Análises')),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<SoilRecord>('soil_records').listenable(),
        builder: (context, box, child) {
          if (box.isEmpty) {
            return const Center(child: Text('Nenhum registro encontrado.'));
          }
          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (BuildContext context, int index) {
              final record = box.getAt(index);
              return ListTile(
                onTap: () => context.go('/details', extra: record),
                leading: const Icon(Icons.list),
                title: Text(record?.address ?? 'Sem endereço'),
                subtitle: Text(record?.timestamp ?? 'Sem data'),
                trailing: const Icon(Icons.arrow_forward),
              );
            },
          );
        },
      ),
    );
  }
}
