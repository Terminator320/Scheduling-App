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
  String status = 'pending',
}) => AppointmentRecord(
  id: 'a$hour${ids.join()}',
  title: 'Job',
  startTime: DateTime(2026, 5, 16, hour),
  endTime: DateTime(2026, 5, 16, hour + 1),
  employeeIds: ids,
  employeeNames: names,
  status: status,
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

  test('dayJobDotColors gives one dot per job, capped at three', () {
    final colors = dayJobDotColors(
      [
        _appt(ids: ['e1'], hour: 8),
        _appt(ids: ['e2'], hour: 10),
        _appt(ids: ['e3'], hour: 12),
        _appt(ids: ['e4'], hour: 14),
      ],
      const {'e1': _blue, 'e2': _green, 'e3': _amber, 'e4': _red},
    );
    expect(colors, [_blue, _green, _amber]);
  });

  test('dayJobDotColors counts jobs, not distinct people', () {
    final colors = dayJobDotColors(
      [
        _appt(ids: ['e1'], hour: 8),
        _appt(ids: ['e1'], hour: 10),
      ],
      const {'e1': _blue},
    );
    expect(colors, [_blue, _blue]);
  });

  test('dayJobDotColors takes each job first colour-resolvable assignee', () {
    final colors = dayJobDotColors(
      [
        _appt(ids: ['ghost', 'e2']),
      ],
      const {'e2': _green},
    );
    expect(colors, [_green]);
  });

  test('dayJobDotColors still dots a job with no resolvable crew colour', () {
    final colors = dayJobDotColors(
      [
        _appt(ids: const []),
      ],
      const {'e1': _blue},
    );
    expect(colors, [null]);
  });

  test('dayJobDotColors honours a lower cap for the week strip', () {
    final colors = dayJobDotColors(
      [
        _appt(ids: ['e1'], hour: 8),
        _appt(ids: ['e2'], hour: 10),
      ],
      const {'e1': _blue, 'e2': _green},
      max: 1,
    );
    expect(colors, [_blue]);
  });

  test('dayJobDotColors returns empty for an empty day', () {
    expect(dayJobDotColors(const [], const {'e1': _blue}), isEmpty);
  });

  test('dayJobDotColors drops a cancelled job', () {
    // A day whose only visit was called off has to read as free.
    final colors = dayJobDotColors(
      [
        _appt(ids: ['e1'], status: 'cancelled'),
      ],
      const {'e1': _blue},
    );
    expect(colors, isEmpty);
  });

  test('dayJobDotColors still dots a completed job', () {
    // `done` is work that HAPPENED — the day was busy, so it keeps its dot.
    final colors = dayJobDotColors(
      [
        _appt(ids: ['e1'], status: 'done'),
        _appt(ids: ['e2'], hour: 11, status: 'completed'),
      ],
      const {'e1': _blue, 'e2': _green},
    );
    expect(colors, [_blue, _green]);
  });

  test('the cap counts the jobs that survive the cancelled filter', () {
    // Cancelled jobs are dropped BEFORE the cap, so a cancellation early in
    // the day cannot cost a live job its dot.
    final colors = dayJobDotColors(
      [
        _appt(ids: ['e1'], hour: 8, status: 'cancelled'),
        _appt(ids: ['e2'], hour: 9),
        _appt(ids: ['e3'], hour: 10),
        _appt(ids: ['e4'], hour: 11),
      ],
      const {'e1': _blue, 'e2': _green, 'e3': _amber, 'e4': _red},
    );
    expect(colors, [_green, _amber, _red]);
  });

  test('dottedJobsOn is what the semantics count reads', () {
    // The cell speaks this count as the dots' meaning, so it must agree with
    // them about a cancelled visit — and it is UNCAPPED, unlike the dots.
    final day = [
      _appt(ids: ['e1'], hour: 8, status: 'cancelled'),
      _appt(ids: ['e2'], hour: 9),
      _appt(ids: ['e3'], hour: 10),
      _appt(ids: ['e4'], hour: 11),
      _appt(ids: ['e1'], hour: 12),
    ];
    expect(dottedJobsOn(day), hasLength(4));
  });
}
