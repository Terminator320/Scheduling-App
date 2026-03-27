import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/address_suggestion.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class ParsedAddress {
  final String fullAddress;
  final String street;
  final String city;
  final String province;
  final String postalCode;

  ParsedAddress({
    required this.fullAddress,
    required this.street,
    required this.city,
    required this.province,
    required this.postalCode,
  });
}

class GooglePlacesService {
  static final String apiKey = dotenv.env['GOOGLE_MAP_API_KEY'] ?? 'default_key';

  static Future<List<AddressSuggestion>> autocomplete(String input) async {
    if (input.trim().isEmpty) return [];

    final response = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
      },
      body: jsonEncode({
        'input': input,
        'includedRegionCodes': ['ca'],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Autocomplete failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = (data['suggestions'] as List? ?? [])
        .map((e) => AddressSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();

    return suggestions;
  }

  static Future<ParsedAddress> getPlaceDetails(String placeId) async {
    final response = await http.get(
      Uri.parse('https://places.googleapis.com/v1/places/$placeId'),
      headers: {
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'formattedAddress,addressComponents',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Place details failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final components =
    (data['addressComponents'] as List? ?? []).cast<Map<String, dynamic>>();

    String unit = '';
    String streetNumber = '';
    String route = '';
    String city = '';
    String province = '';
    String postalCode = '';

    for (final c in components) {
      final types = (c['types'] as List? ?? []).cast<String>();
      final longText = c['longText'] ?? '';
      final shortText = c['shortText'] ?? '';

      if (types.contains('subpremise')) unit = longText;
      if (types.contains('street_number')) streetNumber = longText;
      if (types.contains('route')) route = longText;
      if (types.contains('locality')) city = longText;
      if (types.contains('administrative_area_level_1')) province = shortText;
      if (types.contains('postal_code')) postalCode = longText;
    }

    final baseStreet = [streetNumber, route]
        .where((e) => e.isNotEmpty)
        .join(' ')
        .trim();

    final street = unit.isNotEmpty && baseStreet.isNotEmpty
        ? '$unit-$baseStreet'
        : baseStreet;

    return ParsedAddress(
      fullAddress: data['formattedAddress'] ?? '',
      street: street,
      city: city,
      province: province,
      postalCode: postalCode,
    );
  }
}