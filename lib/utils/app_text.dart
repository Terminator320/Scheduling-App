import 'package:flutter/material.dart';

import 'app_language.dart';

const Map<String, String> _fr = {
  'Scheduling App': 'Application de planification',
  'Login': 'Connexion',
  'Enter email and password': 'Entrez votre courriel et votre mot de passe',
  'Email': 'Courriel',
  'Password': 'Mot de passe',
  'Sign In': 'Se connecter',
  'Forgot password?': 'Mot de passe oublié ?',
  'Create account': 'Créer un compte',
  'Create Account': 'Créer un compte',
  'Sign in': 'Se connecter',
  'Admin': 'Admin',
  'Settings': 'Paramètres',
  'Profile': 'Profil',
  'Logout': 'Déconnexion',
  'Reset': 'Réinitialiser',
  'Cancel': 'Annuler',
  'Apply': 'Appliquer',
  'Size': 'Taille',
  'Calendar': 'Calendrier',
  'Employees': 'Employés',
  'Clients': 'Clients',
  'Appointments': 'Rendez-vous',
  'Change Font Size': 'Changer la taille du texte',
  'Change to Dark Mode': 'Passer en mode sombre',
  'Change to Light Mode': 'Passer en mode clair',
  'Language': 'Langue',
  'Choose Language': 'Choisir la langue',
  'English': 'Anglais',
  'Français': 'Français',
  'Edit Employees': 'Modifier les employés',
  'Search by name or phone number': 'Rechercher par nom ou numéro de téléphone',
  'Search by name or phone number...': 'Rechercher par nom ou numéro de téléphone...',
  'Create Employee': 'Créer un employé',
  'Enter username and email': 'Entrez le nom d’utilisateur et le courriel',
  'Username': 'Nom d’utilisateur',
  'Value': 'Valeur',
  'Phone number': 'Numéro de téléphone',
  'Employee Color': 'Couleur de l’employé',
  'Employee name': 'Nom de l’employé',
  'Edit Employee': 'Modifier l’employé',
  'Update Employee': 'Mettre à jour l’employé',
  'Employee details': 'Détails de l’employé',
  'Employee color': 'Couleur de l’employé',
  'Edit Clients': 'Modifier les clients',
  'Add Client': 'Ajouter un client',
  'Client name': 'Nom du client',
  'Address': 'Adresse',
  'Edit Client': 'Modifier le client',
  'Update Client': 'Mettre à jour le client',
  'Client details': 'Détails du client',
  'name': 'nom',
  'Name': 'Nom',
  'Event': 'Événement',
  'Event name': 'Nom de l’événement',
  'Event name*': 'Nom de l’événement*',
  'Date': 'Date',
  'Start Time': 'Heure de début',
  'End Time': 'Heure de fin',
  'Client (search by name or phone number)': 'Client (recherche par nom ou téléphone)',
  'Client name (phone number)': 'Nom du client (numéro de téléphone)',
  'Type of job': 'Type de travail',
  'Type of job...': 'Type de travail...',
  'Notes': 'Notes',
  'Materials needed': 'Matériel requis',
  'Pictures': 'Photos',
  'Add New Event': 'Ajouter un événement',
  'Create Event': 'Créer l’événement',
  'Edit Event': 'Modifier l’événement',
  'Update Event': 'Mettre à jour l’événement',
  'Type the note here...': 'Écrivez la note ici...',
  'Type the materials here...': 'Écrivez le matériel ici...',
  'Insert pictures here...': 'Ajoutez les photos ici...',
  'Item 1': 'Article 1',
  'Item 2': 'Article 2',
  'Item 3': 'Article 3',
  'Item 4': 'Article 4',
  'Item 5': 'Article 5',
  'No pictures added': 'Aucune photo ajoutée',
  '1 picture attached': '1 photo jointe',
  '2 pictures attached': '2 photos jointes',
  '3 pictures attached': '3 photos jointes',
  'Event Done': 'Événement terminé',
  'Tap the + button to add one later.': 'Touchez le bouton + pour en ajouter un plus tard.',
  '(Admin Name)': '(Nom de l’admin)',
  'January': 'Janvier',
  'February': 'Février',
  'March': 'Mars',
  'April': 'Avril',
  'May': 'Mai',
  'June': 'Juin',
  'July': 'Juillet',
  'August': 'Août',
  'September': 'Septembre',
  'October': 'Octobre',
  'November': 'Novembre',
  'December': 'Décembre',
  'Sun': 'Dim',
  'Mon': 'Lun',
  'Tue': 'Mar',
  'Wed': 'Mer',
  'Thu': 'Jeu',
  'Fri': 'Ven',
  'Sat': 'Sam',
  'Job title': 'Titre du travail',
  'General appointment notes': 'Notes générales du rendez-vous',
  'Standard tools': 'Outils standards',
  'Customer requested confirmation call': 'Le client a demandé un appel de confirmation',
  'Replacement parts': 'Pièces de remplacement',
  'Access through side entrance': 'Accès par l’entrée latérale',
  'Inspection checklist': 'Liste de vérification d’inspection',
  'Call on arrival': 'Appeler à l’arrivée',
  'Cleaning supplies': 'Fournitures de nettoyage',
  'Bring extra materials': 'Apporter du matériel supplémentaire',
  'Extra fittings': 'Raccords supplémentaires',
  'Change Email': 'Changer le courriel',
  'Admin only': 'Admin seulement',
  'New email': 'Nouveau courriel',
  'Verification email sent. Please confirm the new email address.':
  'Un courriel de vérification a été envoyé. Veuillez confirmer la nouvelle adresse courriel.',
  'Please log in again before changing email':
  'Veuillez vous reconnecter avant de changer le courriel',
  'Email already in use': 'Ce courriel est déjà utilisé',
  'Invalid email': 'Courriel invalide',
  'Error updating email': 'Erreur lors de la modification du courriel',
  'No employees found': 'Aucun employé trouvé',
  'Error loading employees': 'Erreur lors du chargement des employés',
  'Give admin mode access': 'Donner accès au mode admin',
  'Name and email are required': 'Le nom et le courriel sont obligatoires',
  'Employee added successfully': 'Employé ajouté avec succès',
  'An employee with this email already exists':
  'Un employé avec ce courriel existe déjà',
  'Could not create employee': 'Impossible de créer l’employé',
  'Delete employee': 'Supprimer l’employé',
  'Are you sure you want to delete this employee?':
  'Êtes-vous sûr de vouloir supprimer cet employé ?',

};

String tr(BuildContext context, String text) {
  final language = AppLanguageScope.of(context).value;
  if (language == 'fr') {
    return _fr[text] ?? text;
  }
  return text;
}

String trMaybe(BuildContext context, String? text) {
  if (text == null) return '';
  return tr(context, text);
}

List<String> localizedWeekdayShort(BuildContext context) => [
      tr(context, 'Sun'),
      tr(context, 'Mon'),
      tr(context, 'Tue'),
      tr(context, 'Wed'),
      tr(context, 'Thu'),
      tr(context, 'Fri'),
      tr(context, 'Sat'),
    ];

String localizedMonthName(BuildContext context, int month) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return tr(context, months[month - 1]);
}

String noEventsForDate(BuildContext context, DateTime date, {bool monthFirst = false}) {
  final language = AppLanguageScope.of(context).value;
  if (language == 'fr') {
    return 'Aucun événement pour le ${date.day}/${date.month}/${date.year}';
  }
  if (monthFirst) {
    return 'No events for ${date.month}/${date.day}/${date.year}';
  }
  return 'No events for ${date.day}/${date.month}/${date.year}';
}
