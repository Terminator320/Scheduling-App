import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marks every create-flow walkthrough as already seen.
///
/// A form sheet's tour gates on `ModalRoute.isCurrent`, which is true the
/// moment a test pumps the sheet — so on a fresh-install preferences store the
/// tour starts, and showcaseview's tooltip animation repeats forever, which
/// makes `pumpAndSettle` time out. A hub tab can't hit this (a standalone
/// screen has no `HubShellScope`, so it never starts).
///
/// Call this from any test that pumps `AddEventSheet`, `AddClientSheet` or
/// `InvitePersonSheet` and isn't testing the tour itself. It represents a user
/// who has already been through the walkthrough, which is the ordinary case.
///
/// Pass [extra] to keep other preferences the test relies on.
void markFormToursSeen({Map<String, Object> extra = const {}}) {
  SharedPreferences.setMockInitialValues({
    ...extra,
    'tour_seen_tabs': [
      for (final form in TourForm.values) FormTour(form).storageKey,
    ],
  });
}
