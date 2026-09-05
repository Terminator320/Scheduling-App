import 'package:scheduling/features/maps/domain/address_parser.dart';

/// One previous job address, with its unit lifted out when the whole list
/// shares a street.
typedef PreviousAddressRow = ({String full, String? unit});

/// The rows to render, and the street they all share when they do.
typedef PreviousAddressList = ({String? sharedStreet, List<PreviousAddressRow> rows});

/// Groups a client's previous job addresses by street, but ONLY when every
/// entry shares one street AND every entry names a unit.
///
/// A mis-grouped address reads as a different building, so the bar is
/// deliberately high: any address without a unit, any second street, or fewer
/// than two entries and the list renders in full instead.
PreviousAddressList groupPreviousAddresses(List<String> addresses) {
  final seen = <String>{};
  final cleaned = [
    for (final raw in addresses)
      if (raw.trim().isNotEmpty && seen.add(raw.trim())) raw.trim(),
  ];
  if (cleaned.length < 2) {
    return (
      sharedStreet: null,
      rows: [for (final a in cleaned) (full: a, unit: null)],
    );
  }

  final splits = [for (final a in cleaned) AddressParser.splitApt(a)];
  final streets = <String>{};
  for (var i = 0; i < cleaned.length; i++) {
    final split = splits[i];
    if (split == null || split.apt.isEmpty) {
      return (
        sharedStreet: null,
        rows: [for (final a in cleaned) (full: a, unit: null)],
      );
    }
    streets.add(split.street.toLowerCase());
  }
  if (streets.length != 1) {
    return (
      sharedStreet: null,
      rows: [for (final a in cleaned) (full: a, unit: null)],
    );
  }

  final unitSeen = <String>{};
  final rows = <PreviousAddressRow>[];
  for (var i = 0; i < cleaned.length; i++) {
    final split = splits[i]!;
    if (!unitSeen.add(split.apt.toLowerCase())) continue;
    rows.add((full: cleaned[i], unit: split.apt));
  }
  return (sharedStreet: splits.first!.street, rows: rows);
}
