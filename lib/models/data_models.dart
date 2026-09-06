// lib/models/data_models.dart

enum TypeEvenement { jour, nuit, conge, deplacement, autre }

class CourseNote {
  String id;
  String nom;
  String contenu;
  CourseNote({required this.id, required this.nom, required this.contenu});
}

class EvenementDetails {
  final TypeEvenement categorie;
  final String label;

  EvenementDetails({required this.categorie, required this.label});
}