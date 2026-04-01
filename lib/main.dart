import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:visiosoil_app/models/soil_record.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(SoilRecordAdapter());
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
