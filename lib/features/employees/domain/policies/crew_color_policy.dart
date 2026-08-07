import 'package:scheduling/core/theme/design_tokens.dart';

/// How many of the ten crew palette colours are still unclaimed.
///
/// Counts only palette entries — a custom colour someone picked through the
/// swatch dialog is not one of the ten, so it cannot use one up. Feeds the
/// "N colours left" caption under the colour grid.
int availableCrewColorCount(Set<int> usedColors) {
  var left = 0;
  for (final color in AppColors.crewPalette) {
    if (!usedColors.contains(color.toARGB32())) left++;
  }
  return left;
}
