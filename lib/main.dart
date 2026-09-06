// lib/main.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mon App Personnelle',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD97743), // Terracotta chaleureux
          primary: const Color(0xFFD97743),
          secondary: const Color(0xFF4A6B5B), // Vert olive doux
          surface: const Color(0xFFFDFBF7), // Fond papier crémeux vintage
        ),
        scaffoldBackgroundColor: const Color(0xFFFDFBF7),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(), // Lance le conteneur principal avec le Drawer et le Planning par défaut
    );
  }
}

