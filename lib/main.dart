import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/home/home_page.dart';

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