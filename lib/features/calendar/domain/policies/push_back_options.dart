import 'package:scheduling/features/calendar/domain/month_grid.dart';

/// The push-back offsets an admin is offered on an open job, in minutes.
const List<int> pushBackMinutes = [15, 30, 60, 120];

/// The offsets from [pushBackMinutes] that keep a job starting at [start] on
/// its own calendar day.
List<int> pushBackOptionsFor(DateTime start) => [
  for (final minutes in pushBackMinutes)
    if (isSameDate(start.add(Duration(minutes: minutes)), start)) minutes,
];
