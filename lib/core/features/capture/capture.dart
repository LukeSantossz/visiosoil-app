import 'package:flutter/material.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture a amostra aqui'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text(
          'Texto de captura aqui',
          style:TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}