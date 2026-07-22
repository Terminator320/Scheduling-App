import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
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
    expect(
      container.read(tourSeenProvider),
      {AdaptiveDestination.calendar, AdaptiveDestination.settings},
    );
  });

  test('markSeen adds the tab and persists it', () async {
    SharedPreferences.setMockInitialValues({});
    container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSeen(AdaptiveDestination.clients);
    expect(
      container.read(tourSeenProvider),
      contains(AdaptiveDestination.clients),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_tabs'), contains('clients'));
  });

  test('resetAll clears state and storage', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar'],
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
    expect(container.read(tourSeenProvider), {AdaptiveDestination.calendar});
  });
}
