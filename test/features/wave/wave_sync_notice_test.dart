import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/wave_sync_notice.dart';
import 'package:scheduling/l10n/l10n.dart';

WaveSyncSummary _summary({
  int imported = 0,
  int updated = 0,
  int pushedCreated = 0,
  int pushedUpdated = 0,
  int pushedPending = 0,
  int pushedFailed = 0,
  bool pushIncomplete = false,
}) => WaveSyncSummary(
  totalCount: 0,
  imported: imported,
  updated: updated,
  skippedArchived: 0,
  pages: 0,
  pushedCreated: pushedCreated,
  pushedUpdated: pushedUpdated,
  pushedPending: pushedPending,
  pushedFailed: pushedFailed,
  pushIncomplete: pushIncomplete,
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  group('waveSyncNotice', () {
    test('names the destination of every count', () {
      expect(
        waveSyncNotice(
          en,
          _summary(
            pushedCreated: 2,
            pushedUpdated: 3,
            imported: 4,
            updated: 5,
          ),
        ),
        'Synced with Wave — 2 clients added to Wave, 3 clients updated in '
        'Wave, 4 clients added to the app, 5 clients updated in the app.',
      );
    });

    test('drops the parts that moved nothing', () {
      // A one-sided run must read as one clause, not a row of zeros.
      expect(
        waveSyncNotice(en, _summary(imported: 4)),
        'Synced with Wave — 4 clients added to the app.',
      );
    });

    test('a run that moved nothing says so instead of listing zeros', () {
      expect(waveSyncNotice(en, _summary()), en.wave_syncUpToDate);
    });

    test('reports the outbox backlog the interactive push did not reach', () {
      // Without this the admin reads "3 added to Wave" as a finished sync,
      // when 200 clients are still waiting on the scheduled worker.
      expect(
        waveSyncNotice(en, _summary(pushedCreated: 3, pushedPending: 200)),
        'Synced with Wave — 3 clients added to Wave, 200 more still syncing '
        'to Wave.',
      );
    });

    test('a failed push is never reported as up to date', () {
      // A push that threw leaves every counter at zero, exactly like a quiet
      // queue — saying "already up to date" there is an affirmative lie.
      final notice = waveSyncNotice(en, _summary(pushIncomplete: true));
      expect(notice, isNot(en.wave_syncUpToDate));
      expect(notice, contains("couldn't be sent to Wave this time"));
    });

    test('dead-lettered clients are called out, not silently dropped', () {
      // These are not queued and will never retry on their own, so they must
      // not vanish into an otherwise cheerful notice.
      expect(
        waveSyncNotice(en, _summary(imported: 4, pushedFailed: 2)),
        'Synced with Wave — 4 clients added to the app, 2 clients '
        "couldn't be sent to Wave.",
      );
    });

    test('singular and plural forms are both used', () {
      expect(
        waveSyncNotice(en, _summary(pushedCreated: 1, imported: 2)),
        'Synced with Wave — 1 client added to Wave, 2 clients added to the '
        'app.',
      );
    });

    test('composes in French too', () {
      expect(
        waveSyncNotice(fr, _summary(pushedCreated: 2, updated: 1)),
        'Synchronisé avec Wave — 2 clients ajoutés à Wave, 1 client mis à '
        'jour dans l’app.',
      );
    });
  });
}
