import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/navigation/app_destination.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Keep the notifier alive across reads (project testing rule).
    c.listen(tourSeenProvider, (_, _) {});
    return c;
  }

  test('loads persisted tabs after ready resolves', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'settings'],
    });
    container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    // The bare destination names devices already hold still resolve — the
    // TourScope change must not orphan them.
    expect(container.read(tourSeenProvider), {
      const DestinationTour(HubTab.calendar),
      const DestinationTour(PushedDestination.settings),
    });
  });

  test('markSeen adds the tab and persists it', () async {
    SharedPreferences.setMockInitialValues({});
    container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSeen(const DestinationTour(HubTab.clients));
    expect(
      container.read(tourSeenProvider),
      contains(const DestinationTour(HubTab.clients)),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_tabs'), contains('clients'));
  });

  test('a form tour persists under its namespaced key', () async {
    SharedPreferences.setMockInitialValues({});
    container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSeen(const FormTour(TourForm.addAppointment));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_tabs'), ['sheet_addAppointment']);
  });

  test('resetAll clears state and storage', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'sheet_addClient'],
    });
    container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.resetAll();
    expect(container.read(tourSeenProvider), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_tabs'), isEmpty);
  });

  test('unknown stored names are ignored', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'no_such_tab'],
    });
    container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {
      const DestinationTour(HubTab.calendar),
    });
  });
}
