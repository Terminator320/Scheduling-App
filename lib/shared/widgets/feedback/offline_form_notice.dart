import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';

/// Tells a form, up front, that saving it will be refused.
///
/// The entity submit controllers fail fast when offline — an awaited Firestore
/// write only resolves on server ack, so without that guard Save spins until
/// reconnect. What was missing is the other half: nothing in the WIDGET layer
/// read `isOfflineProvider`, so an admin could fill out an entire appointment
/// or client and only learn at Save. The app's global `OfflineBanner` does not
/// cover this — it sits under the page content, and a modal sheet is drawn
/// over the whole screen.
///
/// A [WarningNote], not an error: nothing has failed, and the form is still
/// worth filling in — the connection may be back before they finish. Renders
/// nothing at all when online, so it costs an online form one bool read.
class OfflineFormNotice extends ConsumerWidget {
  const OfflineFormNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isOfflineProvider)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sp16),
      child: WarningNote(
        message: context.l10n.common_offlineFormNotice,
        icon: Icons.cloud_off_rounded,
      ),
    );
  }
}
