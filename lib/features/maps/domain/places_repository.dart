import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/features/maps/domain/models/parsed_address.dart';

/// Repository contract for the Google Places API. Pure Dart so it can be
/// mocked in tests without a `GOOGLE_MAP_API_KEY`.
abstract class PlacesRepository {
  /// Returns up to N suggestions for a free-text query, biased to Canada
  /// and the Montreal area. Empty list when the input is empty or the API
  /// returns no matches.
  Future<List<AddressSuggestion>> autocomplete(String input);

  /// Resolves a `placeId` (from `autocomplete`) into a structured
  /// `ParsedAddress`.
  Future<ParsedAddress> getPlaceDetails(String placeId);
}
