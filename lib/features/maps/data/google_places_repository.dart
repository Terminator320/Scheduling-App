import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/features/maps/data/maps_error_mapper.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/features/maps/domain/maps_failure.dart';
import 'package:scheduling/features/maps/domain/models/address_suggestion.dart';
import 'package:scheduling/features/maps/domain/models/parsed_address.dart';
import 'package:scheduling/features/maps/domain/places_repository.dart';

class GooglePlacesRepository implements PlacesRepository {
  GooglePlacesRepository({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<List<AddressSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) async {
    if (input.trim().isEmpty) return const [];

    final stripped = AddressParser.splitApt(input)?.street ?? input;

    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions.httpsCallable('placesAutocomplete').call({
        'input': stripped,
        'sessionToken': sessionToken,
      });
    } catch (e, st) {
      throw MapsErrorMapper.map(e, st);
    }

    try {
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? const {};
      final suggestions = (data['suggestions'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AddressSuggestion.fromJson(e.cast<String, dynamic>()))
          .toList();
      return suggestions;
    } catch (e, st) {
      throw MapsFailureParse(cause: e, stackTrace: st);
    }
  }

  @override
  Future<ParsedAddress> getPlaceDetails(
    String placeId, {
    required String sessionToken,
  }) async {
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions.httpsCallable('placesGetDetails').call({
        'placeId': placeId,
        'sessionToken': sessionToken,
      });
    } catch (e, st) {
      throw MapsErrorMapper.map(e, st);
    }

    try {
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? const {};
      final components = (data['addressComponents'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      var unit = '';
      var streetNumber = '';
      var route = '';
      var city = '';
      var province = '';
      var postalCode = '';

      for (final c in components) {
        final types = (c['types'] as List? ?? []).cast<String>();
        final longText = (c['longText'] as String?) ?? '';
        final shortText = (c['shortText'] as String?) ?? '';

        if (types.contains('subpremise')) unit = longText;
        if (types.contains('street_number')) streetNumber = longText;
        if (types.contains('route')) route = longText;
        if (types.contains('locality')) city = longText;
        if (types.contains('administrative_area_level_1')) province = shortText;
        if (types.contains('postal_code')) postalCode = longText;
      }

      final baseStreet = [
        streetNumber,
        route,
      ].where((e) => e.isNotEmpty).join(' ').trim();

      final street = unit.isNotEmpty && baseStreet.isNotEmpty
          ? '$unit-$baseStreet'
          : baseStreet;

      return ParsedAddress(
        fullAddress: (data['formattedAddress'] as String?) ?? '',
        street: street,
        city: city,
        province: province,
        postalCode: postalCode,
      );
    } catch (e, st) {
      throw MapsFailureParse(cause: e, stackTrace: st);
    }
  }
}
