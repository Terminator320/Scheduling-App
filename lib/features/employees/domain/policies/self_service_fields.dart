/// The keys a person may write on their OWN `users` doc.
///
/// Hand-mirrors `isAvailabilityOnlyChange()` in `firestore.rules`, which is the
/// real gate — `self_service_fields_test.dart` reads the rules back and fails
/// the build if the two drift. The rules use `hasOnly`, so a write carrying one
/// extra key is rejected in full, never partially applied.
///
/// Adding a key here without adding it there is a silent `permission-denied` on
/// every self save. Adding it *there* first is the safe order.
const Set<String> kSelfServiceUserFields = {
  'workingDays',
  'workStartMinutes',
  'workEndMinutes',
  'onCall',
  'phone',
  'travelAlertsEnabled',
  'updatedAt',
};
