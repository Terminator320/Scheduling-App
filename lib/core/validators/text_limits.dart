class TextLimits {
  const TextLimits._();

  static const int appointmentTitle = 200;
  static const int appointmentAddress = 500;
  static const int appointmentNotes = 4000;
  static const int appointmentMaterials = 2000;

  static const int personName = 200;
  static const int firstName = 200;
  static const int lastName = 200;

  /// Each half of a `users` name. 100, matching `createEmployeeInvite`'s
  /// server cap exactly — a client cap ABOVE the server's lets the field
  /// accept a value the callable then rejects as `invalid-argument`, which
  /// surfaces as an unexplained "Something went wrong" the user cannot fix.
  static const int employeeNameHalf = 100;

  /// 24. Must clear the widest string `formatPhoneNumber` can emit, because
  /// `LabeledTextField` applies the length limiter AFTER the mask: a NANP
  /// number typed with its leading 1 formats to 16 chars and an international
  /// `+` number is passed through untouched, so a 15 cap silently ate the
  /// 11th digit with no error shown. The rules cap stays at 40 — caps there
  /// mirror the widest value a write path can produce, never the client cap.
  static const int phone = 24;
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
