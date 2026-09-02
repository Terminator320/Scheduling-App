import 'package:scheduling/features/calendar/domain/month_grid.dart';

/// The push-back offsets an admin is offered on an open job, in minutes.
const List<int> pushBackMinutes = [15, 30, 60, 120];

/// The offsets from [pushBackMinutes] that keep a job starting at [start] on
/// its own calendar day.
///
/// A job pushed past midnight would change WHICH DAY it runs on: the agenda,
/// the drawer badge and every day-scoped reducer re-scope through `runsOn`,
/// so a 23:30 visit pushed an hour would silently move to tomorrow's list.
/// Those offsets are withheld rather than clamped, so the sheet never offers
/// a shift it cannot honour as a same-day one.
List<int> pushBackOptionsFor(DateTime start) => [
  for (final minutes in pushBackMinutes)
    if (isSameDate(start.add(Duration(minutes: minutes)), start)) minutes,
];
