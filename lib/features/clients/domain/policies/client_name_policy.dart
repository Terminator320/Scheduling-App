/// The stored/displayed split for a client's name.
///
/// **`clients/{id}.name` IS THE WAVE CUSTOMER NAME**, and as of 2026-08-14
/// (owner call) that means two different things depending on who the client
/// is. The field is synced VERBATIM by `toWaveCustomerInput`
/// (`functions/wave/mappers.js`), and it is what shows on Wave's customer list
/// and on an invoice.
///
/// - **A PERSON is named by their phone number, unpunctuated**: "5145551234".
///   That is what the invoicing workflow identifies them by, and Wave wants it
///   bare (owner call 2026-08-16 — the `phone` FIELD is still stored formatted
///   as "(514) 555-1234"). Their real name lives in `firstName`/`lastName`, so
///   nothing is lost.
/// - **A BUSINESS keeps its name**: "3101-5696 qc inc.", "1505 Village de
///   Bergerac". That name is the identity; a number in its place would make
///   the customer unrecognisable, and there is rarely a first/last to fall
///   back on. [ClientNamePolicy.looksLikeBusinessName] is what catches the
///   Wave-imported ones, which carry no `type`.
///
/// **The app never renders `name` for a person.** Every in-app surface reads
/// `ClientRecord.displayName` → [ClientNamePolicy.displayFor]: the first/last
/// halves for a person, the business name for a business — so a card, a search
/// result, an avatar's initials and the `clientName` denormalized onto an
/// appointment all say "Marc Tremblay" or "Vogas Plumbing".
///
/// [ClientNamePolicy.stripPhone] survives for the legacy shape — a stored name
/// that still carries `"<name> <number>"` — and is what the edit sheet seeds
/// from. [ClientNamePolicy.composeStored] is idempotent on both branches,
/// which is what lets the backfill and every ordinary save re-run safely.
///
/// **A SAVE PATH composes through [ClientNamePolicy.composeSave], never
/// [ClientNamePolicy.composeStored] directly** — on a person the composed name
/// IS the phone number, so a doc with no `firstName`/`lastName` would have the
/// typed name overwritten with nothing left holding it. `composeSave` lands it
/// in the halves in the same write.
///
/// **Hand-mirrored in `functions/client_name_utils.js`** (which
/// `propagateClientEdits` and the backfill script both read through). The two
/// share worked examples in their tests — change them together.
library;

import 'package:scheduling/core/validators/phone_format.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';

class ClientNamePolicy {
  const ClientNamePolicy._();

  static final _nonDigit = RegExp(r'\D');

  /// A run of digits and the separators a person types between them, ANYWHERE
  /// in the string. The `\d` at each end keeps a trailing "(" or "-" out of the
  /// match.
  ///
  /// Only ever acted on when it reduces to a clean 10-digit number — see
  /// [_matchPhone], which is what makes this loose pattern safe against a
  /// street number, a postal code or a year.
  static final _candidate = RegExp(r'\+?\d[\d\s().\-]{7,}\d');

  /// A phone-shaped run anchored to the END of the string, with whatever
  /// separator was typed in front of it. Deliberately loose — a match is only
  /// ever ACTED on when its digits equal the doc's own stored number, so this
  /// cannot mistake a street number, a postal code or a year for a phone.
  static final _trailingPhone = RegExp(
    r'[\s,;:\-–—·|]*(\+?\d[\d\s().+\-]{5,}\d)\s*$',
  );

  /// Separator runs at either end. Leading matters for [liftPhoneFromName],
  /// where the number can sit at the FRONT ("514-555-1234 - Marc Tremblay").
  static final _edgeSeparators = RegExp(r'^[\s,;:\-–—·|]+|[\s,;:\-–—·|]+$');

  /// The number's OWN wrapper, at the seam the lift cut it out of.
  ///
  /// [_candidate] starts and ends on a digit, so a number written the way the
  /// app itself renders it — "(514) 555-1234" — leaves its brackets behind,
  /// and a client pasted in that shape was stored named "(". These are
  /// deliberately NOT folded into [_edgeSeparators]: that set is shared with
  /// [stripPhone], where a trailing bracket is usually the name's own
  /// ("Depanneur (Nord)"). Only the characters touching the cut are suspect.
  static final _openSeam = RegExp(r'[\s(]+$');
  static final _closeSeam = RegExp(r'^[\s)]+');

  /// The doc's number reduced to comparable digits. A NANP number typed with
  /// its leading country code ("1-514-555-1234") is the same number as
  /// "(514) 555-1234", so the 11-digit form sheds its leading 1.
  static String _digits(String value) {
    final digits = value.replaceAll(_nonDigit, '');
    if (digits.length == 11 && digits.startsWith('1')) {
      return digits.substring(1);
    }
    return digits;
  }

  static String _trimSeparators(String value) =>
      value.replaceAll(_edgeSeparators, '').trim();

  /// [name] with the client's own trailing phone number removed.
  ///
  /// Returns [name] unchanged when the trailing run is not this client's
  /// number — that is what keeps a business genuinely named with digits
  /// ("Depanneur 2000") intact.
  ///
  /// Returns `''` when the name is nothing BUT the number; callers decide what
  /// to show instead ([displayFor] falls back to the first/last halves).
  static String stripPhone(
    String name, {
    String phone = '',
    String mobile = '',
  }) {
    final base = name.trim();
    if (base.isEmpty) return '';

    // Exact suffix first. This is the shape [composeStored] writes, so an
    // app-written name round-trips losslessly whatever the number looks like —
    // including the international and extension forms `PhoneInputFormatter`
    // deliberately passes through unmasked.
    for (final candidate in [phone.trim(), mobile.trim()]) {
      if (candidate.isEmpty) continue;
      if (base.endsWith(candidate)) {
        return _trimSeparators(
          base.substring(0, base.length - candidate.length),
        );
      }
    }

    // Digit-matched trailing run. Legacy docs were typed with the number in a
    // different shape from the stored one ("Marc Tremblay 514-555-1234" beside
    // a stored "(514) 555-1234"), so an exact suffix misses them.
    final wanted = <String>{
      for (final candidate in [phone, mobile])
        if (_digits(candidate).isNotEmpty) _digits(candidate),
    };
    if (wanted.isEmpty) return base;

    final match = _trailingPhone.firstMatch(base);
    if (match == null) return base;
    if (!wanted.contains(_digits(match.group(1)!))) return base;
    return _trimSeparators(base.substring(0, match.start));
  }

  /// What gets PERSISTED, and what Wave shows as the CUSTOMER name (owner call
  /// 2026-08-14).
  ///
  /// **A PERSON is named by their phone number, BARE** — "5145551234", not the
  /// "(514) 555-1234" the field itself stores — because the invoicing workflow
  /// in Wave identifies people by number and wants it unpunctuated (owner call
  /// 2026-08-16). `phone` keeps its formatting; only the name is reduced, via
  /// the shared [bareNumber]. Their actual name is in `firstName`/`lastName`,
  /// which is what [displayFor] renders in the app, so nothing is lost.
  ///
  /// [stripPhone] recognises the bare form as this client's own number (it
  /// digit-matches, not just suffix-matches), which is what keeps the branch
  /// idempotent across the formatting change.
  ///
  /// **A BUSINESS keeps its name**, because that name IS how Wave identifies
  /// it: "3101-5696 qc inc.", "1505 Village de Bergerac". Replacing it with a
  /// number would make the customer unrecognisable on a real invoice, and
  /// unlike a person there is usually no first/last to fall back on.
  /// [looksLikeBusinessName] is what catches the Wave-imported ones, which
  /// carry no [type] at all.
  ///
  /// Both branches are idempotent, which is what lets the backfill and every
  /// ordinary save re-run: a person's number recomposes to itself, and a
  /// business's name is returned stripped and unchanged.
  ///
  /// [baseName] is also the answer for a person with no number at all — a Wave
  /// customer still needs something to be called, and a blank would float the
  /// doc to the top of the name-ordered client list with no initial for its
  /// avatar.
  static String composeStored({
    required String baseName,
    required String phone,
    String mobile = '',
    ClientType type = ClientType.unset,
    String businessName = '',
  }) {
    final base = stripPhone(baseName, phone: phone, mobile: mobile);
    if (isBusiness(type: type, businessName: businessName) ||
        looksLikeBusinessName(base)) {
      return base;
    }

    final number = phone.trim().isNotEmpty ? phone.trim() : mobile.trim();
    return number.isNotEmpty ? bareNumber(number) : base;
  }

  /// The stored name PLUS the halves that have to carry a person's typed name.
  ///
  /// **Every save path must compose through this, never [composeStored]
  /// directly.** [composeStored] replaces a PERSON's name with their phone
  /// number, so on a doc whose `firstName`/`lastName` are empty the typed name
  /// is the ONLY copy of it and the save destroys it in place — Firestore
  /// keeps no history. That is not hypothetical: it is exactly how the corpus
  /// `functions/scripts/restore-client-name-halves.js` exists to repair was
  /// created, and the Name field is `required` while both halves are
  /// `optional`, so the ordinary create flow reproduces it.
  ///
  /// Landing the name in the halves loses nothing and changes no Wave
  /// identity: [displayFor] reads the halves for a person, and Wave carries
  /// its own first/last fields beside the customer name.
  ///
  /// Three cases deliberately pass through untouched:
  /// - the stored name came back unchanged (a business, or a person with no
  ///   number on file), so nothing was replaced and nothing is at risk;
  /// - a half is already populated — never clobber a name that is there, and
  ///   on a BUSINESS the halves are the CONTACT PERSON, not the client;
  /// - there is no base name to rescue.
  static ({String name, String firstName, String lastName}) composeSave({
    required String baseName,
    required String phone,
    String mobile = '',
    String firstName = '',
    String lastName = '',
    ClientType type = ClientType.unset,
    String businessName = '',
  }) {
    final stored = composeStored(
      baseName: baseName,
      phone: phone,
      mobile: mobile,
      type: type,
      businessName: businessName,
    );
    final first = firstName.trim();
    final last = lastName.trim();
    final kept = (name: stored, firstName: first, lastName: last);

    final base = stripPhone(baseName, phone: phone, mobile: mobile);
    if (stored == base || base.isEmpty) return kept;
    if (first.isNotEmpty || last.isNotEmpty) return kept;

    final halves = splitPersonName(base);
    return (
      name: stored,
      firstName: halves.firstName,
      lastName: halves.lastName,
    );
  }

  /// Splits a person's name into the two stored halves.
  ///
  /// Deliberately dumb — the last whitespace token is the surname and
  /// everything before it is the given name. "Marc Tremblay" and "Jean Paul
  /// Belanger" both come out right; a one-token name becomes a first name with
  /// no last, which [displayFor] renders unchanged. That beats guessing which
  /// half a lone name is.
  ///
  /// Hand-mirrored by `splitName` in
  /// `functions/scripts/backfill-client-name-with-phone.js` (which
  /// `restore-client-name-halves.js` imports rather than re-spelling) — the two
  /// share worked examples.
  static ({String firstName, String lastName}) splitPersonName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return (firstName: '', lastName: '');
    if (parts.length == 1) return (firstName: parts.first, lastName: '');
    return (
      firstName: parts.sublist(0, parts.length - 1).join(' '),
      lastName: parts.last,
    );
  }

  /// Company-name tokens, bounded by non-letters so "Inc." is a business and
  /// "Vincent" is not. Matched against an accent-folded, lowercased name, so
  /// "Ltée" arrives here as "ltee" — a `\b` after "é" would never fire, since
  /// Dart's word boundary is ASCII-only.
  ///
  /// Deliberately short. A false positive only leaves a client named the way
  /// it already was; a false NEGATIVE renames a real customer to a phone
  /// number on live Wave invoices.
  static final _businessToken = RegExp(
    '(^|[^a-z])(inc|ltd|ltee|llc|llp|enr|senc|sencrl|cie|corp|corporation|'
    'company|holdings|group|groupe|services|solutions|technology|'
    'technologies|entreprise|entreprises|immobilier|immeuble|immeubles|'
    'gestion|construction|condo|condos|syndicat|copropriete|residence|'
    r'residences|habitations|logements|appartements)([^a-z]|$)',
  );

  /// ANY digit left in the name once the client's own number is off it —
  /// "1505 Village de Bergerac", "3101-5696 qc inc.", "Condo 706".
  ///
  /// Deliberately blunt, and biased on purpose. A person's name does not
  /// contain digits, so the only false positives are a person carrying a
  /// SECOND, older number in their name — and the cost of that is merely that
  /// they keep the name they already had, which the backfill reports. The
  /// opposite mistake renames a real company on live Wave invoices.
  static final _anyDigit = RegExp(r'\d');

  /// Whether [name] reads as an ORGANIZATION on its face.
  ///
  /// This is the fallback for the docs that carry no `type`: the Wave import
  /// sets none, so every imported business would otherwise read as a person
  /// and be renamed to its phone number. It is a heuristic and it is meant to
  /// be — the backfill lists everything it matches, and everything it renames,
  /// so the call can be checked before a single Wave customer is touched.
  static bool looksLikeBusinessName(String name) {
    final value = name.trim();
    if (value.isEmpty) return false;
    if (_anyDigit.hasMatch(value)) return true;
    final folded = value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e');
    return _businessToken.hasMatch(folded);
  }

  /// The clean name to hand back to [composeStored] when RE-SAVING a stored
  /// client — the stored [name] with its number stripped, never [displayFor].
  ///
  /// The distinction is the whole point, and getting it wrong renames real
  /// Wave customers. `clients/{id}.name` IS Wave's customer name, and on a
  /// business it holds the BUSINESS while `firstName`/`lastName` hold its
  /// contact person. [displayFor] prefers those halves for anything it reads
  /// as a person — including every Wave-imported doc, since the import sets no
  /// `type` — so seeding an edit form from the display name and saving it back
  /// replaces "Vogas Plumbing" with "Marc Tremblay" on live invoices.
  ///
  /// **Dart-only, deliberately — there is no JS twin.** The backfill hands
  /// [composeStored] the RAW stored `name` and stops there, so it never needs
  /// this fallback order; a doc whose name is junk simply composes to its
  /// number. The halves are reached here only when the stored name is empty
  /// once its own number is stripped, which is that same junk case seen from
  /// the edit form, where leaving the field blank is not an option.
  static String baseNameFor({
    required String name,
    String phone = '',
    String mobile = '',
    String firstName = '',
    String lastName = '',
    String businessName = '',
  }) {
    final stored = stripPhone(name, phone: phone, mobile: mobile);
    if (stored.isNotEmpty) return stored;

    final composed = [
      firstName.trim(),
      lastName.trim(),
    ].where((half) => half.isNotEmpty).join(' ');
    if (composed.isNotEmpty) return composed;

    return stripPhone(businessName, phone: phone, mobile: mobile);
  }

  /// Whether this client is an ORGANIZATION rather than a person — which
  /// decides whose name identifies it in [displayFor].
  ///
  /// `propertyManagement` counts: a property-management company is a business
  /// with a contact person, exactly the shape [displayFor] has to get right.
  ///
  /// The legacy `businessName` clause is the second half, and it is not
  /// belt-and-braces: pre-Wave-reshape business docs predate the `type` field
  /// entirely, so they are `unset` and would otherwise be read as people. That
  /// field is only ever populated on a business.
  static bool isBusiness({
    ClientType type = ClientType.unset,
    String businessName = '',
  }) =>
      type == ClientType.commercial ||
      type == ClientType.propertyManagement ||
      businessName.trim().isNotEmpty;

  /// What every in-app surface shows.
  ///
  /// **A BUSINESS shows its business name; a person shows their first/last
  /// halves** (owner call 2026-08-14). The two branches exist because
  /// `firstName`/`lastName` mean different things on the two kinds of client:
  /// on a person they ARE the client, and on a business they are only its
  /// contact person — so preferring them everywhere would render "Vogas
  /// Plumbing" as "Marc Tremblay" on the card for a commercial job.
  ///
  /// For a person the halves win over the stored [name] because [name] is
  /// Wave's field: it carries the phone number, and on an imported customer it
  /// is whatever Wave had.
  ///
  /// Every branch ends at the same three fallbacks, just in a different order,
  /// so a client missing the field its own branch prefers still renders
  /// something. The last resort is the raw [name] — a bare number beats an
  /// empty string, which would float the doc to the top of the name-ordered
  /// list with no initial for its avatar.
  static String displayFor({
    required String name,
    // REQUIRED, and deliberately not defaulted: `ClientType.unset` reads as a
    // PERSON, so a default here made "I forgot to pass the type" and "this
    // client genuinely has no type" the same call — and dropping the argument
    // would silently render every commercial client as its contact person on
    // every card, tile and appointment, with the suite still green.
    required ClientType type,
    String phone = '',
    String mobile = '',
    String firstName = '',
    String lastName = '',
    String businessName = '',
  }) {
    final base = stripPhone(name, phone: phone, mobile: mobile);
    final composed = [
      firstName.trim(),
      lastName.trim(),
    ].where((half) => half.isNotEmpty).join(' ');

    if (isBusiness(type: type, businessName: businessName)) {
      // `name` first: that is where the business itself lives, and the legacy
      // `businessName` is only reached on a doc whose `name` is blank or was
      // nothing but a phone number.
      if (base.isNotEmpty) return base;
      final business = stripPhone(businessName, phone: phone, mobile: mobile);
      if (business.isNotEmpty) return business;
      // No company name on file at all — the contact person is better than
      // rendering the phone number.
      if (composed.isNotEmpty) return composed;
      return name.trim();
    }

    // No `businessName` leg here, and that is not an omission: `isBusiness` is
    // true for ANY non-empty `businessName`, so on this branch it is provably
    // blank. Resolving it up front cost two regex passes on every read of a
    // person's name, which is per row on every list and search rebuild.
    if (composed.isNotEmpty) return composed;
    if (base.isNotEmpty) return base;
    return name.trim();
  }

  /// Moves a phone number the admin typed or pasted into the NAME field over
  /// into the phone field, and takes it back out of the name.
  ///
  /// Returns null when there is nothing to do — which is the common case, so
  /// callers can use it as their "did anything change" test.
  ///
  /// Two rules carried over from the one-off backfill this replaces:
  /// a typed phone always WINS (an existing [phone] means the name's number is
  /// a duplicate or a second line, and guessing between them is worse than
  /// leaving it), and a name that is NOTHING but the number keeps it — the
  /// name is required, so emptying the field would look like the paste
  /// vanished.
  static ({String name, String phone})? liftPhoneFromName({
    required String name,
    required String phone,
  }) {
    if (phone.trim().isNotEmpty) return null;
    final match = _matchPhone(name);
    if (match == null) return null;

    final before = name
        .substring(0, match.start)
        .replaceAll(_openSeam, '');
    final after = name.substring(match.end).replaceAll(_closeSeam, '');
    final remaining = _trimSeparators('$before $after');
    if (remaining.isEmpty) return (name: name, phone: match.formatted);
    return (name: remaining, phone: match.formatted);
  }

  static ({int start, int end, String formatted})? _matchPhone(String text) {
    for (final match in _candidate.allMatches(text)) {
      final candidate = match.group(0)!;
      // An international number has no fixed shape, so bracketing its first
      // three digits as an area code would be wrong. Leave it in the name.
      if (candidate.contains('+')) continue;
      if (_digits(candidate).length != 10) continue;
      return (
        start: match.start,
        end: match.end,
        formatted: formatPhoneNumber(_digits(candidate)),
      );
    }
    return null;
  }
}
