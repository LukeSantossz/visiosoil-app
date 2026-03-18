import 'package:flutter/material.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico De Análises'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text(
          'Texto de Histórico aqui',
          style:TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}