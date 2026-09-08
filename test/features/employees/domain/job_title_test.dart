import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations fr;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  group('jobTitleLabel', () {
    test('a picked title renders its own label', () {
      expect(
        JobTitle.pickable.map((t) => jobTitleLabel(en, t)),
        ['Lead tech', 'Technician', 'Apprentice', 'Dispatcher'],
      );
    });

    test('an unpicked title renders nothing, not a placeholder', () {
      // `unset` is a normal state — the admin never chose — so it must render
      // as absent rather than as a fifth title.
      expect(jobTitleLabel(en, JobTitle.unset), isEmpty);
    });

    test('every pickable title is translated', () {
      for (final title in JobTitle.pickable) {
        expect(
          jobTitleLabel(fr, title),
          isNotEmpty,
          reason: '${title.raw} has no French label',
        );
      }
    });
  });

  group('JobTitle.isAssignable', () {
    test('a dispatcher is not crew', () {
      expect(JobTitle.dispatcher.isAssignable, isFalse);
    });

    test('every other title is', () {
      for (final title in JobTitle.values) {
        if (title == JobTitle.dispatcher) continue;
        expect(title.isAssignable, isTrue, reason: title.raw);
      }
    });
  });

  group('JobTitle.fromRaw', () {
    test('a stored value round-trips', () {
      expect(JobTitle.fromRaw('lead_tech'), JobTitle.leadTech);
    });

    test('an unknown value falls back to unset', () {
      expect(JobTitle.fromRaw('foreman'), JobTitle.unset);
    });

    test('a null value falls back to unset', () {
      expect(JobTitle.fromRaw(null), JobTitle.unset);
    });
  });
}
