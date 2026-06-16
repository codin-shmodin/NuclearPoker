import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'theme/app_theme.dart';

class NuclearPokerApp extends StatelessWidget {
  const NuclearPokerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NuclearPoker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
