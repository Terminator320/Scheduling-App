import 'package:scheduling/l10n/l10n.dart';

/// Every supported locale's spelling of the "Personal" title placeholder.
/// A top-level `final` is already initialized lazily, so this costs nothing
/// until the first day off is rendered.
///
/// The placeholder is written into the stored title in the AUTHOR's locale
/// (`add_appointment_sheet.dart`, `details_edit_body.dart`) and read back in
/// the READER's, so a single `context.l10n.calendar_personal` is the wrong
/// test: a French admin's untitled block stores "Personnel", an English
/// reader compares it against "Personal", the match misses, and the headline
/// reads "Personnel" — the exact outcome [dayOffReason] exists to prevent.
/// It also misses in reverse, and on every record already on disk.
final Set<String> personalTitlePlaceholders = {
  for (final locale in AppLocalizations.supportedLocales)
    lookupAppLocalizations(locale).calendar_personal,
};

/// The reason typed on a day off, or null when there is none to lead with.
///
/// Owned in one place because BOTH surfaces that render a day off — the
/// agenda strip (`_DayOffStrip`) and the opened view (`_DayOffBody`) — put the
/// reason first and the person second, and they have to agree on what counts
/// as "no reason". Two things do, and the second is the trap:
///
///  * **The placeholder.** An unnamed personal block does NOT save blank.
///    `add_appointment_sheet.dart` stores the localized "Personal" string when
///    the title field is left empty, so that value is what "untitled" actually
///    looks like on disk. Led with, every untitled day off would read
///    "Personal" — which is precisely why both surfaces name the person instead.
///  * **No subject.** With nobody assigned, the title is already serving as
///    the subject of the sentence ("Vacation is off"), so there is no separate
///    reason left to put above it.
///
/// Pass [personalTitlePlaceholders] for [placeholders] — the match is
/// case-insensitive on the trimmed value, and must cover EVERY locale rather
/// than the reader's alone. See that set for why.
String? dayOffReason({
  required String title,
  required bool hasSubject,
  required Set<String> placeholders,
}) {
  if (!hasSubject) return null;
  final trimmed = title.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  for (final placeholder in placeholders) {
    if (placeholder.trim().toLowerCase() == lower) return null;
  }
  return trimmed;
}
