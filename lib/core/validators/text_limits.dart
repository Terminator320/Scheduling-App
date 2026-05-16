/// Field length caps enforced at the form / validator / repository
/// boundary. Firestore caps a single doc at 1 MiB; without these caps a
/// stray paste or hostile client can blow up indexes, cost, and listener
/// payloads. The numbers below are chosen to be generous for legitimate
/// use while keeping any single doc well under the Firestore limit.
class TextLimits {
  const TextLimits._();

  // Appointment fields.
  static const int appointmentTitle = 200;
  static const int appointmentAddress = 500;
  static const int appointmentNotes = 4000;
  static const int appointmentMaterials = 2000;

  // Person fields (clients, employees, contacts).
  static const int personName = 200;
  static const int phone = 32;
  static const int email = 320;

  // Postal address components.
  static const int aptUnit = 32;
  static const int city = 100;
  static const int province = 100;
  static const int postalCode = 16;
  static const int country = 100;

  // Free-form client notes.
  static const int clientNotes = 4000;
}
