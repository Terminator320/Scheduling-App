import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/utils/client_booking_context_scope.dart';

AppointmentRecord _visit(DateTime start, {String address = ''}) =>
    AppointmentRecord(
      startTime: start,
      endTime: start.add(const Duration(hours: 2)),
      address: address,
    );

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  final now = DateTime(2026, 9, 5, 14);

  test('a future booking is not the last visit', () {
    final context = clientBookingContextOf([
      _visit(DateTime(2026, 10, 12), address: '1250 boul. LaSalle'),
      _visit(DateTime(2026, 8, 20), address: '1250 boul. LaSalle'),
    ], now: now);
    expect(context.lastVisitLabel, isNotNull);
    expect(context.lastVisitLabel, isNot(contains('Oct')));
  });

  test('a client with only future bookings has no last visit', () {
    final context = clientBookingContextOf([
      _visit(DateTime(2026, 10, 12), address: 'a'),
    ], now: now);
    expect(context.lastVisitLabel, isNull);
    expect(context.previousAddresses, ['a']);
  });

  test('addresses are de-duplicated and capped', () {
    final context = clientBookingContextOf([
      for (var i = 0; i < 30; i++)
        _visit(DateTime(2026, 8, 20), address: 'unit $i'),
      _visit(DateTime(2026, 8, 20), address: 'unit 0'),
    ], now: now);
    expect(context.previousAddresses, hasLength(kBookingPreviousAddressLimit));
    expect(context.previousAddresses.toSet(), hasLength(
      kBookingPreviousAddressLimit,
    ));
  });

  test('blank addresses are dropped', () {
    final context = clientBookingContextOf([
      _visit(DateTime(2026, 8, 20), address: '   '),
      _visit(DateTime(2026, 8, 20), address: '1250 boul. LaSalle'),
    ], now: now);
    expect(context.previousAddresses, ['1250 boul. LaSalle']);
  });

  test('a visit EARLIER TODAY is the last visit', () {
    final context = clientBookingContextOf([
      _visit(DateTime(2026, 9, 5, 9), address: 'a'),
      _visit(DateTime(2026, 8, 20), address: 'b'),
    ], now: now);
    // The cut is an instant, not midnight — a job that ran this morning has
    // happened, and reading past it showed the previous visit instead.
    expect(context.lastVisitLabel, isNotNull);
    expect(context.lastVisitLabel, isNot(contains('Aug')));
  });

  test('a booking LATER TODAY is still not the last visit', () {
    final context = clientBookingContextOf([
      _visit(DateTime(2026, 9, 5, 18), address: 'a'),
    ], now: now);
    expect(context.lastVisitLabel, isNull);
  });
}
