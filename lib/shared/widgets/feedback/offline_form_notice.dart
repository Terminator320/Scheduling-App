import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';

/// Tells a form, up front, that saving it will be refused.
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
