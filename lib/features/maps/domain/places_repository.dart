import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/features/maps/domain/models/parsed_address.dart';

/// Repository contract for the Google Places API. Pure Dart so it can be
/// mocked in tests without exercising Cloud Functions.
abstract class PlacesRepository {
  /// Returns up to N suggestions for a free-text query, biased to Canada
  /// and the Montreal area. Empty list when the input is empty or the API
  /// returns no matches.
  ///
  /// [sessionToken] is forwarded to Places API so the autocomplete + details
  /// calls are billed as a single session. Callers generate one UUID per
  /// editing session and discard it after `getPlaceDetails` returns.
  Future<List<AddressSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  });

  /// Resolves a `placeId` (from `autocomplete`) into a structured
  /// `ParsedAddress`. See [autocomplete] for [sessionToken] semantics.
  Future<ParsedAddress> getPlaceDetails(
    String placeId, {
    required String sessionToken,
  });
}
