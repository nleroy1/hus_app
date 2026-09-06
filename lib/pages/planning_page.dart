// lib/pages/planning_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // Import pour le stockage local
import '../models/data_models.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  final String scriptUrl = "https://script.google.com/macros/s/AKfycbz_5zVeNdOK64Qas3pu0w7aD34941FwjR9-ANjRxTFIDjAixVaKzAdcSkEGpWJNePeHOg/exec";
  static const String _cacheKey = 'planning_events_cache';

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isInitialized = false;
  bool _isLoading = false;

  final Map<DateTime, List<EvenementDetails>> _evenements = {};
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null).then((_) async {
      setState(() {
        _isInitialized = true;
      });
      
      // 1. Charger immédiatement le dernier backup local (dispo instantanément hors-ligne)
      await _chargerDonneesLocales();

      // 2. Tenter de rafraîchir en arrière-plan depuis le réseau si disponible
      _chargerDonneesDistantes();
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // --- GESTION DU CACHE LOCAL (HORS-LIGNE) ---

  Future<void> _chargerDonneesLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        final decodedMap = jsonDecode(cachedData) as Map<String, dynamic>;
        Map<DateTime, List<EvenementDetails>> tempEvents = {};

        decodedMap.forEach((dateStr, eventsList) {
          DateTime date = DateTime.parse(dateStr);
          List<EvenementDetails> evs = (eventsList as List).map((e) {
            TypeEvenement type = TypeEvenement.values.firstWhere(
              (t) => t.name == e['categorie'],
              orElse: () => TypeEvenement.autre,
            );
            return EvenementDetails(categorie: type, label: e['label']);
          }).toList();
          tempEvents[date] = evs;
        });

        setState(() {
          _evenements.clear();
          _evenements.addAll(tempEvents);
        });
      }
    } catch (e) {
      debugPrint("Erreur lecture cache local : $e");
    }
  }

  Future<void> _sauvegarderDonneesLocales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> encoderMap = {};

      _evenements.forEach((date, evs) {
        encoderMap[date.toIso8601String()] = evs.map((e) => {
          'categorie': e.categorie.name,
          'label': e.label,
        }).toList();
      });

      await prefs.setString(_cacheKey, jsonEncode(encoderMap));
    } catch (e) {
      debugPrint("Erreur écriture cache local : $e");
    }
  }

  // --- CHARGEMENT DISTANT (AVEC GESTION DU RÉSEAU) ---

  Future<void> _chargerDonneesDistantes() async {
    // On n'affiche le loader visuel que si on n'a vraiment aucune donnée affichée
    if (_evenements.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await http.get(Uri.parse("$scriptUrl?action=get")).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List rows = data['events'];
          
          Map<DateTime, List<EvenementDetails>> tempEvents = {};

          for (var row in rows) {
            int? day = row['d_day'];
            int? month = row['d_month'];
            int? year = row['d_year'];
            String catStr = row['categorie'] ?? 'autre';
            String label = row['label'] ?? '';

            if (day != null && month != null && year != null) {
              DateTime dateNormalisee = DateTime(year, month + 1, day);
              
              TypeEvenement type = TypeEvenement.autre;
              String catLower = catStr.toLowerCase();
              
              if (catLower == 'jour' || catLower.contains('jour')) {
                type = TypeEvenement.jour;
              } else if (catLower == 'nuit' || catLower.contains('nuit')) {
                type = TypeEvenement.nuit;
              } else if (catLower == 'deplacement' || catLower.contains('deplacement')) {
                type = TypeEvenement.deplacement;
              } else if (catLower == 'conge' || catLower.contains('conge')) {
                type = TypeEvenement.conge;
              } else {
                type = TypeEvenement.autre;
              }

              tempEvents.putIfAbsent(dateNormalisee, () => []);
              tempEvents[dateNormalisee]!.add(EvenementDetails(categorie: type, label: label));
            }
          }

          setState(() {
            _evenements.clear();
            _evenements.addAll(tempEvents);
          });

          // Sauvegarde automatique du nouveau backup local après un succès réseau
          await _sauvegarderDonneesLocales();
        }
      }
    } catch (e) {
      debugPrint("Mode hors-ligne ou erreur réseau : $e");
      // L'application continue d'utiliser tranquillement les données du cache local sans bloquer l'utilisateur.
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sauvegarderEvenement(DateTime date, TypeEvenement type, String defaultLabel) async {
    final dateNormalisee = DateTime(date.year, date.month, date.day);
    String comment = _commentController.text.trim();
    
    String finalLabel = defaultLabel;
    if (defaultLabel.isEmpty) {
      finalLabel = comment;
    } else if (comment.isNotEmpty) {
      finalLabel = "$defaultLabel: $comment";
    }

    String dateStr = "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

    setState(() {
      _evenements.putIfAbsent(dateNormalisee, () => []);
      _evenements[dateNormalisee]!.add(EvenementDetails(categorie: type, label: finalLabel));
      _isLoading = true;
    });

    // Sauvegarde immédiate dans le cache local
    await _sauvegarderDonneesLocales();

    try {
      await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode({
          "action": "save",
          "dateStr": dateStr,
          "category": type.name,
          "label": defaultLabel,
          "comment": comment,
        }),
      );
    } catch (e) {
      debugPrint("Action enregistrée localement, mais échec de transmission réseau (Hors-ligne) : $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enregistré hors-ligne (synchronisation ultérieure requise)")),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _effacerJour(DateTime date) async {
    final dateNormalisee = DateTime(date.year, date.month, date.day);
    String dateStr = "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

    setState(() {
      _evenements.remove(dateNormalisee);
      _isLoading = true;
    });

    // Mise à jour immédiate du cache local
    await _sauvegarderDonneesLocales();

    try {
      await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode({
          "action": "clear",
          "dateStr": dateStr,
        }),
      );
    } catch (e) {
      debugPrint("Erreur suppression réseau : $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<EvenementDetails> _getEvenementsPourJour(DateTime day) {
    final dateNormalisee = DateTime(day.year, day.month, day.day);
    return _evenements[dateNormalisee] ?? [];
  }

  Color _getCouleurEvenement(TypeEvenement type) {
    switch (type) {
      case TypeEvenement.jour: return const Color(0xFFFFB3B3);
      case TypeEvenement.nuit: return const Color(0xFFB3D9FF);
      case TypeEvenement.conge: return const Color(0xFFFFD700);
      case TypeEvenement.deplacement: return const Color(0xFFD1B3FF);
      case TypeEvenement.autre: return const Color(0xFFE0E0E0);
    }
  }

  Color _getTextColorEvenement(TypeEvenement type) {
    switch (type) {
      case TypeEvenement.jour: return const Color(0xFF7b241c);
      case TypeEvenement.nuit: return const Color(0xFF0e6251);
      case TypeEvenement.conge: return const Color(0xFF7e5109);
      case TypeEvenement.deplacement: return const Color(0xFF512e5f);
      case TypeEvenement.autre: return const Color(0xFF333333);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text("Mon Planning")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mon Planning Pro"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _chargerDonneesDistantes,
            tooltip: "Synchroniser",
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: TableCalendar(
                  locale: 'fr_FR',
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: CalendarFormat.month,
                  shouldFillViewport: true,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    _afficherOptionsDate(context, selectedDay);
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                  },
                  calendarStyle: const CalendarStyle(
                    outsideDaysVisible: false,
                  ),
                  calendarBuilders: CalendarBuilders(
                    selectedBuilder: (context, day, focusedDay) => _buildDayCell(day, isSelected: true),
                    todayBuilder: (context, day, focusedDay) => _buildDayCell(day, isToday: true),
                    defaultBuilder: (context, day, focusedDay) => _buildDayCell(day),
                  ),
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildDayCell(DateTime day, {bool isSelected = false, bool isToday = false}) {
    final evs = _getEvenementsPourJour(day);

    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: isToday ? Colors.blue.withValues(alpha: 0.05) : Colors.white,
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: isToday ? Colors.blueAccent : Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: evs.length,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final ev = evs[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 1.0),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: _getCouleurEvenement(ev.categorie),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    ev.label,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: _getTextColorEvenement(ev.categorie),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _afficherOptionsDate(BuildContext context, DateTime date) {
    _commentController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Modifier la journée du ${date.day}/${date.month}/${date.year}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: "Note (ex: Barbecue, RDV...)",
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 15),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              childAspectRatio: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB3B3)),
                  onPressed: () {
                    _sauvegarderEvenement(date, TypeEvenement.jour, "J");
                    Navigator.pop(context);
                  },
                  child: const Text("Jour (J)", style: TextStyle(color: Colors.black87)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB3D9FF)),
                  onPressed: () {
                    _sauvegarderEvenement(date, TypeEvenement.nuit, "N");
                    Navigator.pop(context);
                  },
                  child: const Text("Nuit (N)", style: TextStyle(color: Colors.black87)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD1B3FF)),
                  onPressed: () {
                    _sauvegarderEvenement(date, TypeEvenement.deplacement, "Déplacement");
                    Navigator.pop(context);
                  },
                  child: const Text("Déplacement", style: TextStyle(color: Colors.black87)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
                  onPressed: () {
                    _sauvegarderEvenement(date, TypeEvenement.conge, "C");
                    Navigator.pop(context, true);
                  },
                  child: const Text("Congé (C)", style: TextStyle(color: Colors.black87)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9b59b6),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  _sauvegarderEvenement(date, TypeEvenement.autre, "");
                  Navigator.pop(context);
                },
                child: const Text("Note Seule"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () {
                  _effacerJour(date);
                  Navigator.pop(context);
                },
                child: const Text("🗑️ Tout effacer ce jour"),
              ),
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }
}