class TextLimits {
  const TextLimits._();

  static const int appointmentTitle = 200;
  static const int appointmentAddress = 500;
  static const int appointmentNotes = 4000;
  static const int appointmentMaterials = 2000;

  static const int personName = 200;
  static const int firstName = 200;
  static const int lastName = 200;
  /// 15, which fits the formatted `(514) 555-1234` (14) with one to spare.
  /// The rules cap stays at 40 — caps there mirror the widest value a write
  /// path can produce (createEmployeeInvite accepts 40), never the client cap.
  static const int phone = 15;
  static const int mobile = 32;
  static const int email = 320;

  static const int aptUnit = 32;
  static const int city = 100;
  static const int province = 100;
  static const int postalCode = 16;
  static const int country = 100;

  static const int clientAccessNotes = 500;
  static const int clientOnSiteManager = 200;
  static const int clientBillingTerms = 200;

  static const int employeeEmergencyContact = 200;

  static const int signupCode = 32;
}
