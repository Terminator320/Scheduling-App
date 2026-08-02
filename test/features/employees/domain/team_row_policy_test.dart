import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/policies/team_row_policy.dart';
import 'package:scheduling/l10n/l10n.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    l10n = await _en();
  });

  test('title and count join with a middot', () {
    expect(
      teamRowSubtitle(
        l10n: l10n,
        jobTitle: JobTitle.leadTech,
        jobsToday: 3,
        email: 'theo@x.com',
      ),
      'Lead tech · 3 jobs today',
    );
  });

  test('no jobs today drops the count, not the title', () {
    expect(
      teamRowSubtitle(
        l10n: l10n,
        jobTitle: JobTitle.technician,
        jobsToday: 0,
        email: 'theo@x.com',
      ),
      'Technician',
    );
  });

  test('no job title leaves the count alone', () {
    expect(
      teamRowSubtitle(
        l10n: l10n,
        jobTitle: JobTitle.unset,
        jobsToday: 2,
        email: 'theo@x.com',
      ),
      '2 jobs today',
    );
  });

  test('with neither, the email carries the row', () {
    expect(
      teamRowSubtitle(
        l10n: l10n,
        jobTitle: JobTitle.unset,
        jobsToday: 0,
        email: 'theo@x.com',
      ),
      'theo@x.com',
    );
  });

  test('one job reads singular', () {
    expect(
      teamRowSubtitle(
        l10n: l10n,
        jobTitle: JobTitle.unset,
        jobsToday: 1,
        email: 'theo@x.com',
      ),
      '1 job today',
    );
  });
}
