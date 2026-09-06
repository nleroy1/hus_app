// lib/pages/budget_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final String scriptUrl = "https://script.google.com/macros/s/AKfycbzv6U1t775NxbBU7V4pqTIoAI4d7AmFRkoGCuNyBz2FfnlJ-qdBBJ7pQKesWQSU9Qju/exec";
  String _moisSelectionne = "Septembre";
  final String _anneeSelectionnee = "2026";
  final List<String> _listeMois = ["Janvier", "Fevrier", "Mars", "Avril", "Mai", "Juin", "Juillet", "Aout", "Septembre", "Octobre", "Novembre", "Decembre"];

  // 0 = Budget Prévisionnel, 1 = Dépenses Réelles
  int _ongletActif = 0; 

  bool _isLoading = false;
  Map<String, dynamic>? _donneesBudget;
  List<dynamic> _donneesReelles = [];

  @override
  void initState() {
    super.initState();
    _initialiserDonnees(_moisSelectionne, _anneeSelectionnee);
  }

  // --- GESTION CACHE LOCAL & RÉSEAU ---
  Future<void> _initialiserDonnees(String mois, String annee) async {
    // 1. Affiche immédiatement les données du cache s'il y en a
    await _chargerDonneesLocales(mois, annee);
    // 2. Lance la synchronisation réseau silencieuse
    _chargerToutesLesDonnees(mois, annee);
  }

  Future<void> _chargerDonneesLocales(String mois, String annee) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? budgetCache = prefs.getString('budget_${mois}_$annee');
      final String? reellesCache = prefs.getString('reelles_${mois}_$annee');

      setState(() {
        if (budgetCache != null) _donneesBudget = jsonDecode(budgetCache);
        if (reellesCache != null) _donneesReelles = jsonDecode(reellesCache);
      });
    } catch (e) {
      debugPrint("Erreur lecture cache budget : $e");
    }
  }

  Future<void> _chargerToutesLesDonnees(String mois, String annee) async {
    // Affiche le loader seulement si aucune donnée n'est affichée (premier lancement du mois)
    if (_donneesBudget == null && _donneesReelles.isEmpty) {
      setState(() => _isLoading = true);
    }
    
    await Future.wait([
      _chargerBudget(mois, annee),
      _chargerDepensesReelles(mois, annee),
    ]);
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _chargerBudget(String mois, String annee) async {
    try {
      final response = await http.get(Uri.parse("$scriptUrl?action=getBudget&mois=$mois"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() => _donneesBudget = data);
          }
          // Sauvegarde en cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('budget_${mois}_$annee', jsonEncode(data));
        }
      }
    } catch (e) {
      debugPrint("Erreur budget réseau/hors-ligne : $e");
    }
  }

  Future<void> _chargerDepensesReelles(String mois, String annee) async {
    try {
      final response = await http.get(Uri.parse("$scriptUrl?action=getReelles&mois=$mois&annee=$annee"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() => _donneesReelles = data['lignesReelles'] ?? []);
          }
          // Sauvegarde en cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('reelles_${mois}_$annee', jsonEncode(_donneesReelles));
        } else {
          if (mounted) setState(() => _donneesReelles = []);
        }
      }
    } catch (e) {
      debugPrint("Erreur réelles réseau/hors-ligne : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Finances • $_moisSelectionne $_anneeSelectionnee"),
        backgroundColor: const Color(0xFFD97743),
        foregroundColor: Colors.white,
        actions: [
          DropdownButton<String>(
            value: _moisSelectionne,
            dropdownColor: const Color(0xFFFDFBF7),
            underline: const SizedBox(),
            items: _listeMois.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
            onChanged: (val) {
              if (val != null) {
                // On vide l'affichage avant de charger le nouveau mois
                setState(() {
                  _moisSelectionne = val;
                  _donneesBudget = null;
                  _donneesReelles = [];
                });
                _initialiserDonnees(val, _anneeSelectionnee);
              }
            },
          ),
          const SizedBox(width: 15),
        ],
      ),
      body: Column(
        children: [
          // Sélecteur de sous-page (Boutons style onglets)
          Container(
            color: const Color(0xFFFDFBF7),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ongletActif == 0 ? const Color(0xFFD97743) : Colors.grey[200],
                      foregroundColor: _ongletActif == 0 ? Colors.white : Colors.black87,
                    ),
                    onPressed: () => setState(() => _ongletActif = 0),
                    child: const Text("Budget Prévisionnel", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ongletActif == 1 ? const Color(0xFFD97743) : Colors.grey[200],
                      foregroundColor: _ongletActif == 1 ? Colors.white : Colors.black,
                    ),
                    onPressed: () => setState(() => _ongletActif = 1),
                    child: const Text("Dépenses Réelles", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          
          // Contenu dynamique selon l'onglet choisi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _ongletActif == 0
                    ? _construireVueBudget()
                    : _construireVueReelles(),
          ),
        ],
      ),
    );
  }

  // --- VUE 1 : BUDGET PRÉVISIONNEL ---
  Widget _construireVueBudget() {
    final budgetMensuel = (_donneesBudget?['budgetMensuel'] ?? 0.0).toDouble();
    final salaires = _donneesBudget?['salaires'] ?? {'nathan': 0.0, 'manon': 0.0};
    final parts = _donneesBudget?['parts'] ?? {'nathan': 0.0, 'manon': 0.0};
    final double salaireNathan = (salaires['nathan'] ?? 0.0).toDouble();
    final double salaireManon = (salaires['manon'] ?? 0.0).toDouble();
    final double partNathan = (parts['nathan'] ?? 0.0).toDouble();
    final double partManon = (parts['manon'] ?? 0.0).toDouble();
    final lignes = _donneesBudget?['lignes'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text("Budget Mensuel", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  Text("${budgetMensuel.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD97743))),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text("Nathan", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4A6B5B))),
                          Text("${salaireNathan.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 16)),
                          Text("Part : ${partNathan.toStringAsFixed(1)}€", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text("Manon", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC89F53))),
                          Text("${salaireManon.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 16)),
                          Text("Part : ${partManon.toStringAsFixed(1)}€", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Détail des Dépenses Prévisionnelles", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lignes.length,
            itemBuilder: (context, index) {
              final ligne = lignes[index];
              double depenseVal = (ligne['depense'] ?? 0.0).toDouble();
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(ligne['libelle'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${ligne['categorie']} • [${ligne['qui']}]"),
                  trailing: Text("${depenseVal.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFD97743))),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // --- VUE 2 : DÉPENSES RÉELLES + BALANCE & TOTAL DÉPENSES ---
  Widget _construireVueReelles() {
    double totalReelCommun = 0.0;
    double totalDepensesCommunesAbs = 0.0;
    Map<String, double> depensesReellesParCategorie = {};

    for (var l in _donneesReelles) {
      if ((l['qui'] ?? '').toString().toLowerCase().contains('commun')) {
        double montant = (l['montant'] ?? 0.0).toDouble();
        totalReelCommun += montant; // Balance globale (revenus + dépenses)
        
        // Uniquement les dépenses (négatives) pour le camembert et le total dépenses
        if (montant < 0) {
          String categorie = (l['categorie'] ?? 'Autre').toString().trim();
          double montantAbs = montant.abs();
          depensesReellesParCategorie.update(categorie, (v) => v + montantAbs, ifAbsent: () => montantAbs);
          totalDepensesCommunesAbs += montantAbs;
        }
      }
    }

    final List<Color> couleursChart = [
      const Color(0xFFD97743),
      const Color(0xFF4A6B5B),
      const Color(0xFFC89F53),
      const Color(0xFF5B7CA3),
      const Color(0xFFA35B5B),
      const Color(0xFF7CA35B),
    ];

    int colorIndex = 0;
    List<PieChartSectionData> sectionsCamembertReel = depensesReellesParCategorie.entries.map((entry) {
      final color = couleursChart[colorIndex % couleursChart.length];
      colorIndex++;
      double pourcentage = totalDepensesCommunesAbs > 0 ? (entry.value / totalDepensesCommunesAbs) * 100 : 0;

      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: '${pourcentage.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Carte des indicateurs (Balance & Total Dépenses)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Ligne 1 : Balance
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Balance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        "${totalReelCommun.toStringAsFixed(2)} €",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: totalReelCommun >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Ligne 2 : Total Dépenses (uniquement négatives)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Total Dépenses", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                      Text(
                        "-${totalDepensesCommunesAbs.toStringAsFixed(2)} €",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Camembert Réel Communs (Dépenses uniquement)
          if (depensesReellesParCategorie.isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Répartition Réelle des Dépenses (Communs)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(sectionsSpace: 2, centerSpaceRadius: 40, sections: sectionsCamembertReel),
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: depensesReellesParCategorie.entries.map((entry) {
                int index = depensesReellesParCategorie.keys.toList().indexOf(entry.key);
                Color color = couleursChart[index % couleursChart.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text("${entry.key} (${entry.value.toStringAsFixed(2)} €)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
          ],

          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Transactions réelles", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          _donneesReelles.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text("Aucune donnée trouvée pour ce mois.", style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _donneesReelles.length,
                  itemBuilder: (context, index) {
                    final reel = _donneesReelles[index];
                    double montant = (reel['montant'] ?? 0.0).toDouble();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(reel['libelle'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${reel['categorie']} • [${reel['qui']}] • ${reel['date'] ?? ''}"),
                        trailing: Text(
                          "${montant.toStringAsFixed(2)} €",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: montant < 0 ? Colors.red : Colors.green),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}