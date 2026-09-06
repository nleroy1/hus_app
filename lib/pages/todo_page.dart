// lib/pages/todo_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final String scriptUrl = "https://script.google.com/macros/s/AKfycbxobaeHnpB5i6Awa23J2bzbOk3hwEDyTsPbMRlDAdUfoI_mZwEkT8PPbQMW-KyA2X4P/exec";
  static const String _cacheKey = 'todo_cache';

  List<Map<String, dynamic>> _todos = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialiserDonnees();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initialiserDonnees() async {
    await _chargerDonneesLocales();
    _chargerTodos();
  }

  // --- CACHE LOCAL ---
  Future<void> _chargerDonneesLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        setState(() {
          _todos = List<Map<String, dynamic>>.from(jsonDecode(cachedData));
        });
      }
    } catch (e) {
      debugPrint("Erreur lecture cache todo : $e");
    }
  }

  Future<void> _sauvegarderDonneesLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_todos));
    } catch (e) {
      debugPrint("Erreur écriture cache todo : $e");
    }
  }

  // --- RÉSEAU ---
  Future<void> _chargerTodos() async {
    if (_todos.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(Uri.parse("$scriptUrl?action=getTodos"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _todos = List<Map<String, dynamic>>.from(
                (data['todos'] ?? []).map((item) => {
                  'titre': item['titre'].toString(),
                  'fait': item['fait'] == true,
                }),
              );
            });
          }
          await _sauvegarderDonneesLocales();
        }
      }
    } catch (e) {
      debugPrint("Erreur chargement todos (mode hors-ligne) : $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _synchroniserAvecSheet() async {
    setState(() => _isSyncing = true);
    try {
      await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode({
          "action": "syncTodos",
          "todos": _todos,
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tâches synchronisées ! ☁️"), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint("Erreur synchro todo : $e");
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // --- ACTIONS LOCALES ---
  void _ajouterTacheLocal(String titre) {
    if (titre.trim().isEmpty) return;
    setState(() {
      _todos.insert(0, {'titre': titre.trim(), 'fait': false});
    });
    _controller.clear();
    _sauvegarderDonneesLocales();
    _synchroniserAvecSheet();
  }

  void _basculerTacheLocal(int index, bool? val) {
    setState(() {
      _todos[index]['fait'] = val ?? false;
    });
    _sauvegarderDonneesLocales();
    _synchroniserAvecSheet();
  }

  void _supprimerTacheLocal(int index) {
    setState(() {
      _todos.removeAt(index);
    });
    _sauvegarderDonneesLocales();
    _synchroniserAvecSheet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("À faire 📝"),
        backgroundColor: const Color(0xFFD97743),
        foregroundColor: Colors.white,
        actions: [
          if (_isSyncing)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_sync),
              tooltip: "Forcer la synchro",
              onPressed: _synchroniserAvecSheet,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "Nouvelle tâche...",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (val) => _ajouterTacheLocal(val),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97743),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _ajouterTacheLocal(_controller.text),
                  child: const Text("Ajouter", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _todos.isEmpty
                      ? const Center(child: Text("Aucune tâche à faire 🎉", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _todos.length,
                          itemBuilder: (context, index) {
                            final todo = _todos[index];
                            bool estFait = todo['fait'] ?? false;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: Checkbox(
                                  activeColor: const Color(0xFFD97743),
                                  value: estFait,
                                  onChanged: (val) => _basculerTacheLocal(index, val),
                                ),
                                title: Text(
                                  todo['titre'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: estFait ? TextDecoration.lineThrough : null,
                                    color: estFait ? Colors.grey : Colors.black87,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _supprimerTacheLocal(index),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}