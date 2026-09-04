import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

const int kSearchTokenQueryLimit = 10;
const int kSearchTokenFieldLimit = 240;

List<String> searchQueryTokens(String query) {
  final text = ClientSearchPolicy.normalize(query);
  final digits = ClientSearchPolicy.digitsOnly(query);
  final tokens = <String>{};
  for (final word in text.split(' ')) {
    if (word.isEmpty) continue;
    tokens.add('t:$word');
  }
  if (digits.isNotEmpty) tokens.add('p:$digits');
  return tokens.take(kSearchTokenQueryLimit).toList();
}

List<String> searchIndexTokens({
  required Iterable<String> texts,
  required Iterable<String> phones,
}) {
  final tokens = <String>{};
  for (final value in texts) {
    for (final word in ClientSearchPolicy.normalize(value).split(' ')) {
      if (word.isEmpty) continue;
      final max = word.length.clamp(1, 24);
      for (var i = 1; i <= max; i++) {
        tokens.add('t:${word.substring(0, i)}');
      }
    }
  }
  for (final phone in phones) {
    final digits = ClientSearchPolicy.digitsOnly(phone);
    if (digits.isEmpty) continue;
    for (var start = 0; start < digits.length; start++) {
      final remaining = digits.length - start;
      if (remaining < 3) break;
      final max = remaining.clamp(3, 12);
      for (var len = 3; len <= max; len++) {
        tokens.add('p:${digits.substring(start, start + len)}');
      }
    }
  }
  return tokens.take(kSearchTokenFieldLimit).toList();
}
