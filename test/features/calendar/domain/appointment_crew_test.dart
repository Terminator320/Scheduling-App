import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/appointment_crew.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

const _blue = Color(0xFF005CC8);
const _green = Color(0xFF0E9B6E);
const _amber = Color(0xFFE08A00);
const _red = Color(0xFFD61F3A);

AppointmentRecord _appt({
  required List<String> ids,
  List<String> names = const [],
  int hour = 9,
}) => AppointmentRecord(
  id: 'a$hour${ids.join()}',
  title: 'Job',
  startTime: DateTime(2026, 5, 16, hour),
  endTime: DateTime(2026, 5, 16, hour + 1),
  employeeIds: ids,
  employeeNames: names,
);

void main() {
  test('crewFor prefers the live name map', () {
    final crew = crewFor(
      _appt(ids: ['e1'], names: ['Stale Name']),
      colorMap: const {'e1': _blue},
      nameMap: const {'e1': 'Theo Bell'},
    );
    expect(crew, hasLength(1));
    expect(crew.single.name, 'Theo Bell');
    expect(crew.single.color, _blue);
  });

  test('crewFor falls back to the denormalized names positionally', () {
    final crew = crewFor(
      _appt(ids: ['e1', 'e2'], names: ['Theo Bell', 'Ana Ruiz']),
      colorMap: const {'e1': _blue, 'e2': _green},
    );
    expect(crew.map((c) => c.name), ['Theo Bell', 'Ana Ruiz']);
    expect(crew.map((c) => c.color), [_blue, _green]);
  });

  test('crewFor keeps an assignee whose colour is unknown', () {
    final crew = crewFor(
      _appt(ids: ['gone'], names: ['Removed Person']),
      colorMap: const {},
    );
    expect(crew.single.name, 'Removed Person');
    expect(crew.single.color, isNull);
  });

  test('crewFor drops an assignee with no resolvable name', () {
    final crew = crewFor(
      _appt(ids: ['e1', 'ghost']),
      colorMap: const {'e1': _blue},
      nameMap: const {'e1': 'Theo Bell'},
    );
    expect(crew, hasLength(1));
    expect(crew.single.name, 'Theo Bell');
  });

  test('crewFor returns empty for an unassigned job', () {
    expect(crewFor(_appt(ids: const []), colorMap: const {}), isEmpty);
  });

  test('dayCrewColors dedupes assignees across the day and caps at three', () {
    final colors = dayCrewColors(
      [
        _appt(ids: ['e1', 'e2'], hour: 8),
        _appt(ids: ['e1'], hour: 10),
        _appt(ids: ['e3'], hour: 12),
        _appt(ids: ['e4'], hour: 14),
      ],
      const {'e1': _blue, 'e2': _green, 'e3': _amber, 'e4': _red},
    );
    expect(colors, [_blue, _green, _amber]);
  });

  test('dayCrewColors skips ids with no colour', () {
    final colors = dayCrewColors(
      [
        _appt(ids: ['ghost', 'e1']),
      ],
      const {'e1': _blue},
    );
    expect(colors, [_blue]);
  });

  test('dayCrewColors honours a lower cap for the week strip', () {
    final colors = dayCrewColors(
      [
        _appt(ids: ['e1', 'e2']),
      ],
      const {'e1': _blue, 'e2': _green},
      max: 1,
    );
    expect(colors, [_blue]);
  });

  test('dayCrewColors returns empty for an empty day', () {
    expect(dayCrewColors(const [], const {'e1': _blue}), isEmpty);
  });
}
