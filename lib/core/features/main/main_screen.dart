import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/home/home_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _presentscreen = 0;

  final List<Widget> _screens = [
    const HomePage(),
    const HistoryScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_presentscreen],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _presentscreen,
        onTap: (int clicked) {
          setState(() {
            _presentscreen = clicked;
          });
        },

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Histórico'),
        ],
      ),
    );
  }
}
