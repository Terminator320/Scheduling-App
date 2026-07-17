import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/features/maps/domain/models/parsed_address.dart';

abstract class PlacesRepository {
  Future<List<AddressSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  });

  Future<ParsedAddress> getPlaceDetails(
    String placeId, {
    required String sessionToken,
  });

  Future<String?> reverseGeocode({
    required double lat,
    required double lng,
    required String locale,
  });
}
