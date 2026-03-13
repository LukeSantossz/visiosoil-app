import 'package:flutter/material.dart';

void main(){
  runApp(const VisioSoilApp());
}

class VisioSoilApp extends StatelessWidget {
  const VisioSoilApp({super.key});

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      title: 'VisioSoil',
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('VisioSoil'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            const Text(
              'VisioSoil',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height:16),
            const Text(
              'Análise de solo por imagem',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height:32),
            ElevatedButton(
              onPressed: (){
                print('Botão Capturar Solo Pressionado');
              },
              child: const Text('Capturar Solo'),
            ),
          ],
        ),
      ),
    );
  }
}

