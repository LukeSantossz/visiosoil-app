import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: VisioSoilApp()));
}

class VisioSoilApp extends StatelessWidget {
  const VisioSoilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'VisioSoil',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
    );
  }
}
