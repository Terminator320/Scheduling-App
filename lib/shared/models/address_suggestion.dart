class AddressSuggestion {
  final String placeId;
  final String description;

  AddressSuggestion({
    required this.placeId,
    required this.description,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final placePrediction =
        json['placePrediction'] as Map<String, dynamic>? ?? {};

    final text = placePrediction['text'] as Map<String, dynamic>?;

    return AddressSuggestion(
      placeId: (placePrediction['placeId'] as String?) ?? '',
      description: (text?['text'] as String?) ?? '',
    );
  }
}