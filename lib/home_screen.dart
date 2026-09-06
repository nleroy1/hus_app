// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'pages/planning_page.dart';
import 'pages/courses_page.dart';
import 'pages/todo_page.dart';
import 'pages/budget_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const PlanningPage(),
    const CoursesPage(),
    const TodoPage(),
    const BudgetPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],

      floatingActionButton: Builder(
        builder: (BuildContext context) {
          return FloatingActionButton(
            backgroundColor: const Color(0xFFD97743),
            foregroundColor: Colors.white,
            child: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          );
        },
      ),

      drawer: Drawer(
        backgroundColor: const Color(0xFFFDFBF7),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Color(0xFFD97743),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "hus_app 🌿",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Navigation principale",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month, color: Color(0xFF4A6B5B)),
              title: const Text("Planning", style: TextStyle(fontWeight: FontWeight.bold)),
              selected: _currentIndex == 0,
              selectedTileColor: const Color(0xFF4A6B5B).withValues(alpha: 0.1),
              onTap: () {
                setState(() => _currentIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_basket, color: Color(0xFFD97743)),
              title: const Text("Courses", style: TextStyle(fontWeight: FontWeight.bold)),
              selected: _currentIndex == 1,
              selectedTileColor: const Color(0xFFD97743).withValues(alpha: 0.1),
              onTap: () {
                setState(() => _currentIndex = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_box, color: Color(0xFF5B7CA3)),
              title: const Text("À faire", style: TextStyle(fontWeight: FontWeight.bold)),
              selected: _currentIndex == 2,
              selectedTileColor: const Color(0xFF5B7CA3).withValues(alpha: 0.1),
              onTap: () {
                setState(() => _currentIndex = 2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet, color: Color(0xFFC89F53)),
              title: const Text("Budget", style: TextStyle(fontWeight: FontWeight.bold)),
              selected: _currentIndex == 3,
              selectedTileColor: const Color(0xFFC89F53).withValues(alpha: 0.1),
              onTap: () {
                setState(() => _currentIndex = 3);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}