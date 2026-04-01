import 'package:flutter/material.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'dart:io';

class DetailsPage extends StatelessWidget {
  final SoilRecord? record;
  const DetailsPage({super.key, this.record});

  @override
  Widget build(BuildContext context) {
    if (record == null) {
      return const Center(child: Text('Nenhum registro encontrado.'));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da Classificação'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Image.file(File(record!.imagePath)),
            Text('Endereço: ${record!.address}'),
            Text('Data: ${record!.timestamp}'),
            Text('Latitude: ${record!.latitude}'),
            Text('Longitude: ${record!.longitude}'),
          ],
        ),
      ),
    );
  }
}
