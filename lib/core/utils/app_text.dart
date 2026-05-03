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
  'or': 'ou',
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
  'Search by name or phone number...':
      'Rechercher par nom ou numéro de téléphone...',
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
  'Client (search by name or phone number)':
      'Client (recherche par nom ou téléphone)',
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
  'Tap the + button to add one later.':
      'Touchez le bouton + pour en ajouter un plus tard.',
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
  'Customer requested confirmation call':
      'Le client a demandé un appel de confirmation',
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
  'Back': 'Retour',
  'Reset Password': 'Réinitialiser le mot de passe',
  'Forgot Password': 'Mot de passe oublié ?',
  'Forgot your password?': 'Mot de passe oublié ?',
  'Enter your account email and we\'ll send you a link to reset your password.':
      'Entrez votre courriel et nous vous enverrons un lien pour réinitialiser votre mot de passe.',
  'Send Reset Email': 'Envoyer le courriel de réinitialisation',
  'Back to Sign In': 'Retour à la connexion',
  'Check your email': 'Vérifiez votre courriel',
  'We\'ve sent a password reset link to:':
      'Nous avons envoyé un lien de réinitialisation à :',
  'Please check your email, then come back to the app and sign in with your new password.':
      'Veuillez vérifier votre courriel, puis revenez à l’application et connectez-vous avec votre nouveau mot de passe.',
  'Didn\'t receive the email? Try again':
      'Vous n’avez pas reçu le courriel ? Réessayez',
  'Email is required': 'Le courriel est obligatoire',
  'Enter a valid email address': 'Entrez une adresse courriel valide',
  'No account found for this email address':
      'Aucun compte trouvé pour cette adresse courriel',
  'Too many attempts. Please try again later.':
      'Trop de tentatives. Veuillez réessayer plus tard.',
  'Network error. Check your connection and try again.':
      'Erreur réseau. Vérifiez votre connexion et réessayez.',
  'Could not send reset email':
      'Impossible d’envoyer le courriel de réinitialisation',
  'Password reset email sent. Please check your inbox.':
      'Courriel de réinitialisation envoyé. Veuillez vérifier votre boîte de réception.',
  'Check your inbox': 'Vérifiez votre boîte de réception',
  'If an account exists for this email, a password reset link has been sent.':
      'Si un compte existe pour ce courriel, un lien de réinitialisation a été envoyé.',
  'The email may take a few minutes to arrive. Remember to check your spam folder.':
      'Le courriel peut prendre quelques minutes à arriver. Pensez à vérifier votre dossier de courrier indésirable.',
  'Use a different email': 'Utiliser un autre courriel',
  'Something went wrong': 'Une erreur s’est produite',
  'Please enter your email': 'Veuillez entrer votre courriel',
  'Please enter your password': 'Veuillez entrer votre mot de passe',
  'Please enter a valid email address':
      'Veuillez entrer une adresse courriel valide',
  'Invalid email or password': 'Courriel ou mot de passe invalide',
  'No account found with this email': 'Aucun compte trouvé pour ce courriel',
  'Too many attempts, please try again later':
      'Trop de tentatives. Veuillez réessayer plus tard',
  'Something went wrong, please try again':
      'Une erreur s’est produite. Veuillez réessayer',
  'This account has been disabled': 'Ce compte a été désactivé',
  'An account with this email already exists':
      'Un compte avec ce courriel existe déjà',
  'Password is too weak. Use at least 6 characters':
      'Mot de passe trop faible. Utilisez au moins 6 caractères',
  'Sign-in is temporarily unavailable':
      'La connexion est temporairement indisponible',
  'This email is not authorized to sign up':
      'Ce courriel n’est pas autorisé à créer un compte',
  'Account created. You can now sign in.':
      'Compte créé. Vous pouvez maintenant vous connecter.',
  'No user profile found for this account':
      'Aucun profil utilisateur trouvé pour ce compte',
  'Please log in again and retry': 'Veuillez vous reconnecter et réessayer',
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

String noEventsForDate(
  BuildContext context,
  DateTime date, {
  bool monthFirst = false,
}) {
  final language = AppLanguageScope.of(context).value;
  if (language == 'fr') {
    return 'Aucun événement pour le ${date.day}/${date.month}/${date.year}';
  }
  if (monthFirst) {
    return 'No events for ${date.month}/${date.day}/${date.year}';
  }
  return 'No events for ${date.day}/${date.month}/${date.year}';
}
