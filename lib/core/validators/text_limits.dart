class TextLimits {
  const TextLimits._();

  static const int appointmentTitle = 200;
  static const int appointmentAddress = 500;
  static const int appointmentNotes = 4000;
  static const int appointmentMaterials = 2000;

  static const int personName = 200;
  static const int firstName = 200;
  static const int lastName = 200;

  /// Each half of a `users` name. 100, matching the `createEmployeeAccount`
  /// and `completeEmployeeSetup` server caps exactly — a client cap ABOVE the
  /// server's lets the field
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

  /// 254. An email that is ALSO a sign-in identity, so it passes through
  /// `createEmployeeAccount` / `changeEmployeeEmail`, both of which
  /// `requireString(..., 254)`. A client cap must never be looser than the
  /// callable's, or the field accepts a value the callable rejects as
  /// `invalid-argument` and the admin sees an unexplained "Something went
  /// wrong" they cannot fix by editing. Client records keep [email] (320),
  /// which matches `isValidClientData`.
  static const int authEmail = 254;

  static const int aptUnit = 32;
  static const int city = 100;
  static const int province = 100;
  static const int postalCode = 16;
  static const int country = 100;

  static const int clientAccessNotes = 500;
  static const int clientOnSiteManager = 200;
  static const int clientBillingTerms = 200;

  static const int employeeEmergencyContact = 200;

  /// 300, matching the `fileName` cap the appointment-images subcollection
  /// rule applies (`isBoundedString(request.resource.data.fileName, 300)`).
  /// `ImageStorageService` composes `<millis>_<originalName>` with whatever the
  /// picker hands it, and `appendAppointmentPictures` writes the whole batch in
  /// ONE `WriteBatch` — so a single over-long basename fails the batch with an
  /// opaque `permission-denied` and takes every valid photo beside it down too.
  static const int imageFileName = 300;
}
