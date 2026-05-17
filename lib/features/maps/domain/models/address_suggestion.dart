import 'package:freezed_annotation/freezed_annotation.dart';

part 'address_suggestion.freezed.dart';

@freezed
abstract class AddressSuggestion with _$AddressSuggestion {
  const factory AddressSuggestion({
    @Default('') String placeId,
    @Default('') String description,
  }) = _AddressSuggestion;
  const AddressSuggestion._();

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final placePrediction =
        (json['placePrediction'] as Map?)?.cast<String, dynamic>() ?? {};
    final text = (placePrediction['text'] as Map?)?.cast<String, dynamic>();

    return AddressSuggestion(
      placeId: (placePrediction['placeId'] as String?) ?? '',
      description: (text?['text'] as String?) ?? '',
    );
  }
}
