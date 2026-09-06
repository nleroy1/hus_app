// lib/pages/courses_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  final String scriptUrl = "https://script.google.com/macros/s/AKfycbxobaeHnpB5i6Awa23J2bzbOk3hwEDyTsPbMRlDAdUfoI_mZwEkT8PPbQMW-KyA2X4P/exec";
  static const String _cacheKey = 'courses_cache';

  List<Map<String, dynamic>> _courses = [];
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

  // --- SÉQUENCE DE CHARGEMENT : CACHE D'ABORD, RÉSEAU EN ARRIÈRE-PLAN ---
  Future<void> _initialiserDonnees() async {
    await _chargerDonneesLocales();
    _chargerCourses();
  }

  // --- GESTION DU CACHE LOCAL ---
  Future<void> _chargerDonneesLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        setState(() {
          _courses = List<Map<String, dynamic>>.from(jsonDecode(cachedData));
        });
      }
    } catch (e) {
      debugPrint("Erreur lecture cache courses : $e");
    }
  }

  Future<void> _sauvegarderDonneesLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_courses));
    } catch (e) {
      debugPrint("Erreur écriture cache courses : $e");
    }
  }

  // --- CHARGEMENT DISTANT (RÉSEAU) ---
  Future<void> _chargerCourses() async {
    // N'affiche le loader que si le cache est totalement vide
    if (_courses.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final response = await http.get(Uri.parse("$scriptUrl?action=getCourses"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _courses = List<Map<String, dynamic>>.from(
                (data['courses'] ?? []).map((item) => {
                  'nom': item['nom'].toString(),
                  'achete': item['achete'] == true,
                }),
              );
            });
          }
          await _sauvegarderDonneesLocales();
        }
      }
    } catch (e) {
      debugPrint("Erreur chargement courses (mode hors-ligne) : $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- SYNCHRONISATION CLOUD ---
  Future<void> _synchroniserAvecSheet() async {
    setState(() => _isSyncing = true);
    try {
      await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode({
          "action": "syncCourses",
          "courses": _courses,
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Liste synchronisée avec le Cloud ! ☁️"), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      debugPrint("Erreur synchro : $e");
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // --- ACTIONS LOCALES (SAUVEGARDE CACHE INSTANTANÉE + SYNCHRO CLOUD) ---
  void _ajouterArticleLocal(String nom) {
    if (nom.trim().isEmpty) return;
    setState(() {
      _courses.insert(0, {'nom': nom.trim(), 'achete': false});
    });
    _controller.clear();
    _sauvegarderDonneesLocales();
    _synchroniserAvecSheet();
  }

  void _basculerArticleLocal(int index, bool? val) {
    setState(() {
      _courses[index]['achete'] = val ?? false;
    });
    _sauvegarderDonneesLocales();
    _synchroniserAvecSheet();
  }

  void _supprimerArticleLocal(int index) {
    setState(() {
      _courses.removeAt(index);
    });
    _sauvegarderDonneesLocales();
    _synchroniserAvecSheet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Liste de Courses 🛒"),
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
                      hintText: "Ajouter un article...",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (val) => _ajouterArticleLocal(val),
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
                  onPressed: () => _ajouterArticleLocal(_controller.text),
                  child: const Text("Ajouter", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _courses.isEmpty
                      ? const Center(child: Text("Votre liste de courses est vide 🥕", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _courses.length,
                          itemBuilder: (context, index) {
                            final course = _courses[index];
                            bool estAchete = course['achete'] ?? false;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: Checkbox(
                                  activeColor: const Color(0xFFD97743),
                                  value: estAchete,
                                  onChanged: (val) => _basculerArticleLocal(index, val),
                                ),
                                title: Text(
                                  course['nom'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: estAchete ? TextDecoration.lineThrough : null,
                                    color: estAchete ? Colors.grey : Colors.black87,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _supprimerArticleLocal(index),
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