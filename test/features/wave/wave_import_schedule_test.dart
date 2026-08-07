import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';

void main() {
  group('WaveImportSchedule.fromRaw', () {
    test('maps known wire strings', () {
      expect(WaveImportSchedule.fromRaw('weekly'), WaveImportSchedule.weekly);
      expect(WaveImportSchedule.fromRaw('monthly'), WaveImportSchedule.monthly);
      expect(WaveImportSchedule.fromRaw('off'), WaveImportSchedule.off);
    });

    test('null/empty/unknown fall to off', () {
      expect(WaveImportSchedule.fromRaw(null), WaveImportSchedule.off);
      expect(WaveImportSchedule.fromRaw(''), WaveImportSchedule.off);
      expect(WaveImportSchedule.fromRaw('yearly'), WaveImportSchedule.off);
    });

    test('raw round-trips for every value', () {
      for (final s in WaveImportSchedule.values) {
        expect(WaveImportSchedule.fromRaw(s.raw), s);
      }
    });
  });
}
