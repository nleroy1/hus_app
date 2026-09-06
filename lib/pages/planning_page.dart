// lib/pages/planning_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/data_models.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  final String scriptUrl =
      "https://script.google.com/macros/s/AKfycbz_5zVeNdOK64Qas3pu0w7aD34941FwjR9-ANjRxTFIDjAixVaKzAdcSkEGpWJNePeHOg/exec";
  static const String _cacheKey = 'planning_events_cache';

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isInitialized = false;
  bool _isLoading = false;

  final Map<DateTime, List<EvenementDetails>> _evenements = {};

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatDateStr(DateTime date) {
    return "${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}";
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null).then((_) async {
      setState(() {
        _isInitialized = true;
      });

      await _chargerDonneesLocales();
      _chargerDonneesDistantes();
    });
  }

  // --- GESTION DU CACHE LOCAL ---

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
        encoderMap[date.toIso8601String()] = evs
            .map((e) => {
                  'categorie': e.categorie.name,
                  'label': e.label,
                })
            .toList();
      });

      await prefs.setString(_cacheKey, jsonEncode(encoderMap));
    } catch (e) {
      debugPrint("Erreur écriture cache local : $e");
    }
  }

  // --- CHARGEMENT DISTANT (MANUEL / INITIAL) ---

  Future<void> _chargerDonneesDistantes() async {
    if (_evenements.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await http
          .get(Uri.parse("$scriptUrl?action=get"))
          .timeout(const Duration(seconds: 5));
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
              } else if (catLower == 'deplacement' ||
                  catLower.contains('deplacement')) {
                type = TypeEvenement.deplacement;
              } else if (catLower == 'conge' || catLower.contains('conge')) {
                type = TypeEvenement.conge;
              } else {
                type = TypeEvenement.autre;
              }

              tempEvents.putIfAbsent(dateNormalisee, () => []);
              tempEvents[dateNormalisee]!
                  .add(EvenementDetails(categorie: type, label: label));
            }
          }

          setState(() {
            _evenements.clear();
            _evenements.addAll(tempEvents);
          });

          await _sauvegarderDonneesLocales();
        }
      }
    } catch (e) {
      debugPrint("Mode hors-ligne ou erreur réseau : $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- SYNCHRONISATION EN ARRIÈRE-PLAN ---

  Future<void> _synchroniserJourneeArrierePlan(DateTime date) async {
    final dateNormalisee = DateTime(date.year, date.month, date.day);
    final dateStr = _formatDateStr(date);
    final listEvents = List<EvenementDetails>.from(_evenements[dateNormalisee] ?? []);

    try {
      // 1. Efface la journée sur le serveur
      await http.post(
        Uri.parse(scriptUrl),
        body: jsonEncode({
          "action": "clear",
          "dateStr": dateStr,
        }),
      );

      // 2. Envoie à nouveau les éléments restants
      for (var ev in listEvents) {
        String defaultPrefix = _getDefaultPrefix(ev.categorie);
        String comment = "";

        if (ev.label.contains(" : ")) {
          final parts = ev.label.split(" : ");
          comment = parts.sublist(1).join(" : ");
        } else if (ev.label != defaultPrefix) {
          comment = ev.label;
        }

        await http.post(
          Uri.parse(scriptUrl),
          body: jsonEncode({
            "action": "save",
            "dateStr": dateStr,
            "category": ev.categorie.name,
            "label": defaultPrefix,
            "comment": comment,
          }),
        );
      }
    } catch (e) {
      debugPrint("Échec de la synchro en arrière-plan : $e");
    }
  }

  // --- ACTIONS LOCALES INSTANTANÉES ---

  Future<void> _sauvegarderEvenement(
    DateTime date,
    TypeEvenement type,
    String defaultLabel,
    String comment, {
    int? indexToEdit,
  }) async {
    final dateNormalisee = DateTime(date.year, date.month, date.day);

    String finalLabel = defaultLabel;
    if (defaultLabel.isEmpty) {
      finalLabel = comment;
    } else if (comment.isNotEmpty) {
      finalLabel = "$defaultLabel : $comment";
    }

    // Mise à jour immédiate de l'UI
    setState(() {
      _evenements.putIfAbsent(dateNormalisee, () => []);
      if (indexToEdit != null &&
          indexToEdit < _evenements[dateNormalisee]!.length) {
        _evenements[dateNormalisee]![indexToEdit] =
            EvenementDetails(categorie: type, label: finalLabel);
      } else {
        _evenements[dateNormalisee]!
            .add(EvenementDetails(categorie: type, label: finalLabel));
      }
    });

    // Enregistrement rapide en local puis envoi silencieux
    await _sauvegarderDonneesLocales();
    _synchroniserJourneeArrierePlan(date);
  }

  Future<void> _supprimerEvenementIndex(DateTime date, int index) async {
    final dateNormalisee = DateTime(date.year, date.month, date.day);
    if (_evenements.containsKey(dateNormalisee)) {
      setState(() {
        _evenements[dateNormalisee]!.removeAt(index);
        if (_evenements[dateNormalisee]!.isEmpty) {
          _evenements.remove(dateNormalisee);
        }
      });
      await _sauvegarderDonneesLocales();
      _synchroniserJourneeArrierePlan(date);
    }
  }

  Future<void> _effacerJour(DateTime date) async {
    final dateNormalisee = DateTime(date.year, date.month, date.day);

    setState(() {
      _evenements.remove(dateNormalisee);
    });

    await _sauvegarderDonneesLocales();
    _synchroniserJourneeArrierePlan(date);
  }

  List<EvenementDetails> _getEvenementsPourJour(DateTime day) {
    final dateNormalisee = DateTime(day.year, day.month, day.day);
    return _evenements[dateNormalisee] ?? [];
  }

  String _getDefaultPrefix(TypeEvenement type) {
    switch (type) {
      case TypeEvenement.jour:
        return "J";
      case TypeEvenement.nuit:
        return "N";
      case TypeEvenement.conge:
        return "C";
      case TypeEvenement.deplacement:
        return "Déplacement";
      case TypeEvenement.autre:
        return "";
    }
  }

  Color _getCouleurEvenement(TypeEvenement type) {
    switch (type) {
      case TypeEvenement.jour:
        return const Color(0xFFFFB3B3);
      case TypeEvenement.nuit:
        return const Color(0xFFB3D9FF);
      case TypeEvenement.conge:
        return const Color(0xFFFFD700);
      case TypeEvenement.deplacement:
        return const Color(0xFFD1B3FF);
      case TypeEvenement.autre:
        return const Color(0xFFE0E0E0);
    }
  }

  Color _getTextColorEvenement(TypeEvenement type) {
    switch (type) {
      case TypeEvenement.jour:
        return const Color(0xFF7B241C);
      case TypeEvenement.nuit:
        return const Color(0xFF0E6251);
      case TypeEvenement.conge:
        return const Color(0xFF7E5109);
      case TypeEvenement.deplacement:
        return const Color(0xFF512E5F);
      case TypeEvenement.autre:
        return const Color(0xFF333333);
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
                    titleTextStyle:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    selectedBuilder: (context, day, focusedDay) =>
                        _buildDayCell(day, isSelected: true),
                    todayBuilder: (context, day, focusedDay) =>
                        _buildDayCell(day, isToday: true),
                    defaultBuilder: (context, day, focusedDay) =>
                        _buildDayCell(day),
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

  Widget _buildDayCell(DateTime day,
      {bool isSelected = false, bool isToday = false}) {
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
              _twoDigits(day.day),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
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

  // --- MODALE DE DÉTAIL ET D'ÉDITION ---

  void _afficherOptionsDate(BuildContext context, DateTime date) {
    TypeEvenement selectedType = TypeEvenement.jour;
    int? editingIndex;
    final TextEditingController noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final events = _getEvenementsPourJour(date);

            void reinitialiserFormulaire() {
              setModalState(() {
                editingIndex = null;
                selectedType = TypeEvenement.jour;
                noteController.clear();
              });
            }

            void chargerPourEdition(int index) {
              final ev = events[index];
              setModalState(() {
                editingIndex = index;
                selectedType = ev.categorie;

                String defaultPrefix = _getDefaultPrefix(ev.categorie);
                if (ev.label.contains(" : ")) {
                  noteController.text =
                      ev.label.split(" : ").sublist(1).join(" : ");
                } else if (ev.label != defaultPrefix) {
                  noteController.text = ev.label;
                } else {
                  noteController.clear();
                }
              });
            }

            Widget buildCategoryTile(TypeEvenement type, String label) {
              final isSelected = selectedType == type;
              final color = _getCouleurEvenement(type);
              final textColor = _getTextColorEvenement(type);

              return InkWell(
                onTap: () {
                  setModalState(() {
                    selectedType = type;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.black87 : Colors.transparent,
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSelected)
                        Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: Icon(Icons.check_circle,
                              size: 16, color: textColor),
                        ),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Journée du ${_formatDateStr(date)}",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Événements enregistrés :",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          if (events.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text("Aucun élément pour ce jour.",
                                  style: TextStyle(color: Colors.grey)),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: events.length,
                              itemBuilder: (ctx, index) {
                                final ev = events[index];
                                final isEditingThis = editingIndex == index;

                                return Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getCouleurEvenement(ev.categorie)
                                        .withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                    border: isEditingThis
                                        ? Border.all(
                                            color: Colors.blue, width: 2)
                                        : null,
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: Chip(
                                      label: Text(
                                        ev.categorie.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _getTextColorEvenement(
                                              ev.categorie),
                                        ),
                                      ),
                                      backgroundColor:
                                          _getCouleurEvenement(ev.categorie),
                                    ),
                                    title: Text(
                                      ev.label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              size: 20, color: Colors.blue),
                                          onPressed: () =>
                                              chargerPourEdition(index),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              size: 20, color: Colors.red),
                                          onPressed: () async {
                                            await _supprimerEvenementIndex(
                                                date, index);
                                            setModalState(() {});
                                            reinitialiserFormulaire();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                          const SizedBox(height: 12),
                          const Divider(),

                          Text(
                            editingIndex == null
                                ? "Ajouter un élément :"
                                : "Modifier l'élément sélectionné :",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 10),

                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            childAspectRatio: 2.8,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              buildCategoryTile(
                                  TypeEvenement.jour, "Jour (J)"),
                              buildCategoryTile(
                                  TypeEvenement.nuit, "Nuit (N)"),
                              buildCategoryTile(
                                  TypeEvenement.deplacement, "Déplacement"),
                              buildCategoryTile(
                                  TypeEvenement.conge, "Congé (C)"),
                              buildCategoryTile(
                                  TypeEvenement.autre, "Autre / Note"),
                            ],
                          ),

                          const SizedBox(height: 12),

                          TextField(
                            controller: noteController,
                            decoration: const InputDecoration(
                              labelText: "Note / Détail (ex : Barbecue, RDV...)",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              if (editingIndex != null)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: OutlinedButton(
                                      onPressed: reinitialiserFormulaire,
                                      child: const Text("Annuler"),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4A6B5B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  onPressed: () async {
                                    final defaultPrefix =
                                        _getDefaultPrefix(selectedType);
                                    final note = noteController.text.trim();

                                    await _sauvegarderEvenement(
                                      date,
                                      selectedType,
                                      defaultPrefix,
                                      note,
                                      indexToEdit: editingIndex,
                                    );

                                    setModalState(() {});
                                    reinitialiserFormulaire();
                                  },
                                  child: Text(editingIndex == null
                                      ? "Ajouter"
                                      : "Mettre à jour"),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if (events.isNotEmpty)
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                icon: const Icon(Icons.delete_forever),
                                label: const Text("Tout effacer pour ce jour"),
                                onPressed: () async {
                                  await _effacerJour(date);
                                  setModalState(() {});
                                  reinitialiserFormulaire();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}