import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/policies/crew_color_policy.dart';

void main() {
  test('a fresh roster has the whole palette left', () {
    expect(availableCrewColorCount(const {}), AppColors.crewPalette.length);
  });

  test('each palette colour taken reduces the count', () {
    final taken = {
      AppColors.crewPalette[0].toARGB32(),
      AppColors.crewPalette[1].toARGB32(),
    };
    expect(availableCrewColorCount(taken), AppColors.crewPalette.length - 2);
  });

  test('a custom colour outside the palette does not reduce the count', () {
    expect(availableCrewColorCount({0xFF123456}), AppColors.crewPalette.length);
  });

  test('never reports a negative count', () {
    final all = {
      for (final c in AppColors.crewPalette) c.toARGB32(),
      0xFF123456,
    };
    expect(availableCrewColorCount(all), 0);
  });
}
