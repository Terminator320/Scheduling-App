// TODO(george): remove this whole file before App Store submission (#pre-ship)
/// Temporary affordances that exist only to make manual testing bearable. Each
/// one is a deliberate hole in shipping behaviour, so they live together in one
/// file that can be deleted outright rather than hunted for.
library;

import 'package:flutter/foundation.dart';

/// Shows a destructive "Delete client" action on the client detail so junk test
/// data can be cleared. Product decision 2026-08-01 is that clients are **never**
/// removed — deleting one orphans its past appointments, which keep the
/// denormalized `clientName` but lose the `clientId` link — so this must not
/// ship.
///
/// Debug-only by default, which means it physically cannot reach the App Store
/// even if the pre-ship sweep misses it. **TestFlight and App Distribution
/// builds are release mode and will NOT show it** — flip this to `true` if you
/// need it there, and flip it back before submitting.
///
/// Restoring this also required restoring `allow delete` on `/clients` in
/// `firestore.rules`; rules are not build-aware, so that hole is open in
/// production regardless of this flag. Remove both together.
// TODO(george): remove with the client delete affordance (#pre-ship)
const bool kShowTestingDeleteClient = kDebugMode;
