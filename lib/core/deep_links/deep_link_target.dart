/// What an inbound `esproschedule://` URL asks the app to open.
sealed class DeepLinkTarget {
  const DeepLinkTarget();
}

/// `esproschedule://appointment?id=...` — opens the appointment detail sheet.
class AppointmentLink extends DeepLinkTarget {
  const AppointmentLink(this.id);

  final String id;
}

/// `esproschedule://invite?code=...` — prefills the invite code screen. The
/// code is a credential: it rides the navigator args and is never logged.
class InviteLink extends DeepLinkTarget {
  const InviteLink(this.code);

  final String code;
}

/// Nothing to do — a foreign scheme, an unknown host, or a URL the
/// `home_widget` channel already owns.
class IgnoredLink extends DeepLinkTarget {
  const IgnoredLink();
}

/// Pure classification of an inbound URL. Every routing decision the
/// dispatcher makes starts here so the branches can be pinned by unit tests.
DeepLinkTarget classifyDeepLink(Uri uri) {
  if (uri.scheme != 'esproschedule') return const IgnoredLink();
  // The home_widget channel owns widget/Live-Activity/Siri taps until the two
  // retire together (ios/CLAUDE.md). Handling them here too would open the
  // appointment sheet twice per tap — both plugins observe the same openURL.
  if (uri.queryParameters.containsKey('homeWidget')) return const IgnoredLink();
  return switch (uri.host) {
    'appointment' => AppointmentLink(uri.queryParameters['id']?.trim() ?? ''),
    'invite' => InviteLink(uri.queryParameters['code']?.trim() ?? ''),
    _ => const IgnoredLink(),
  };
}
