import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/example_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final figTitle = ref.watch(grayTitleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('VisioSoil'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'VisioSoil',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              figTitle,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              
              onPressed: () {
                context.push('/capture');
                print('Botão Capturar Solo Pressionado');
              },
              child: const Text('Capturar Solo'),
            ),
            ElevatedButton(
              onPressed: () {
                context.push('/history');
                print('Botão Acessar Histórico Pressionado');
              },
              child: const Text('Acessando Histórico'),
            ),
          ],
        ),
      ),
    );
  }
}
