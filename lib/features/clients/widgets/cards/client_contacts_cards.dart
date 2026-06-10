import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/email_compose_launcher.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/info_card.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Section of additional business [contacts], each an [InfoCard] with tappable
/// phone (call) and email (compose) rows. Shared by the client and appointment
/// detail views; renders nothing when [contacts] is empty.
class ClientContactsCards extends ConsumerWidget {
  const ClientContactsCards({required this.contacts, super.key});

  final List<ClientContact> contacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (contacts.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp24),
        SectionLabel(context.l10n.common_contacts),
        const SizedBox(height: AppSpacing.sp8),
        for (final contact in contacts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
            child: InfoCard(
              rows: [
                if (contact.name.isNotEmpty)
                  InfoCardRow(
                    icon: Icons.person_outline,
                    text: contact.name,
                    iconColor: scheme.secondary,
                    emphasize: true,
                  ),
                if (contact.phone.isNotEmpty)
                  InfoCardRow(
                    icon: Icons.phone_outlined,
                    text: contact.phone,
                    onTap: () => launchPhoneCall(context, ref, contact.phone),
                    trailingIcon: Icons.chevron_right,
                  ),
                if (contact.email.isNotEmpty)
                  InfoCardRow(
                    icon: Icons.email_outlined,
                    text: contact.email,
                    onTap: () => EmailComposeLauncher.showEmailChoices(
                      context,
                      ref,
                      email: contact.email,
                    ),
                    trailingIcon: Icons.chevron_right,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
