import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Keep the notifier alive across reads (project testing rule).
    c.listen(tourSeenProvider, (_, _) {});
    return c;
  }

  test('loads persisted step ids after ready resolves', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_steps': ['calendarGrid', 'settingsReplay'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {
      TourStepId.calendarGrid,
      TourStepId.settingsReplay,
    });
  });

  test('an id that no longer exists is dropped, not resurrected', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_steps': ['calendarGrid', 'retiredStepFromAnOldBuild'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {TourStepId.calendarGrid});
  });

  test('migrates the legacy per-scope flags into step ids', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'sheet_addClient'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    final seen = container.read(tourSeenProvider);
    // Every 1.57 step of a seen scope counts as seen...
    expect(seen, contains(TourStepId.calendarGrid));
    expect(seen, contains(TourStepId.calendarDayRoute));
    expect(seen, contains(TourStepId.clientSave));
    // ...but a step added after 1.57 does not, or nobody would ever see it.
    expect(seen, isNot(contains(TourStepId.calendarWeekToggle)));
    expect(seen, isNot(contains(TourStepId.calendarCrewFilter)));
    // A scope the device never saw contributes nothing.
    expect(seen, isNot(contains(TourStepId.dashboardHero)));
    // The migration persists, so it only runs once.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), contains('calendarGrid'));
  });

  test('an unknown legacy scope key is ignored by the migration', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['someRetiredTab'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), isEmpty);
  });

  test('an existing step list wins over the legacy flags', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar'],
      'tour_seen_steps': ['settingsReplay'],
    });
    final container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {TourStepId.settingsReplay});
  });

  test('markSteps adds the ids and persists them', () async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSteps([TourStepId.jobStart, TourStepId.jobMarkDone]);
    expect(container.read(tourSeenProvider), {
      TourStepId.jobStart,
      TourStepId.jobMarkDone,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), contains('jobStart'));
  });

  test(
    'markSteps with nothing new leaves the state and storage alone',
    () async {
      SharedPreferences.setMockInitialValues({
        'tour_seen_steps': ['calendarGrid'],
      });
      final container = newContainer();
      final notifier = container.read(tourSeenProvider.notifier);
      await notifier.ready;
      final before = container.read(tourSeenProvider);

      // Already seen, so this must early-return rather than re-notify.
      await notifier.markSteps([TourStepId.calendarGrid]);

      expect(identical(container.read(tourSeenProvider), before), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('tour_seen_steps'), ['calendarGrid']);
    },
  );

  test('resetAll clears storage without re-migrating', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar'],
    });
    final container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    expect(container.read(tourSeenProvider), isNotEmpty);
    await notifier.resetAll();
    expect(container.read(tourSeenProvider), isEmpty);
    // An EMPTY list is still a PRESENT key, so a later load must not pull the
    // legacy flags back in — that would undo the replay the user just asked
    // for.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_steps'), isEmpty);
    final second = newContainer();
    await second.read(tourSeenProvider.notifier).ready;
    expect(second.read(tourSeenProvider), isEmpty);
  });
}
