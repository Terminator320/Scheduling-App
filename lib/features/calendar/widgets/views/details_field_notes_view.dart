import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/application/field_notes_provider.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/field_note.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

/// The crew's notes on a job, read-only, shown to ANYONE who may read the job
/// — which is the admin and the assignees, exactly the set the rules admit.
///
/// The dispatcher's brief lives in the appointment's own `notes` and is
/// rendered by the client panel above; this is the other half of that
/// distinction, and the reason the two fields are separate.
class DetailsFieldNotesView extends ConsumerWidget {
  const DetailsFieldNotesView({required this.appointment, super.key});

  final AppointmentRecord appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = appointment.id;
    final stored = id == null
        ? const <FieldNote>[]
        : ref.watch(appointmentFieldNotesProvider(id)).value ??
              const <FieldNote>[];

    final legacy = appointment.fieldNotes.trim();
    final notes = [
      if (legacy.isNotEmpty) FieldNote.legacy(legacy),
      ...stored,
    ];
    // Empty omitted, like every other optional block on this sheet.
    if (notes.isEmpty) return const SizedBox.shrink();

    // Hoisted out of the notes: constructing one parses the locale's symbols.
    final when = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sp16),
        MonoSectionLabel(context.l10n.calendar_crewNotesLabel),
        const SizedBox(height: AppSpacing.sp8),
        for (final note in notes) ...[
          _Note(note: note, when: when),
          const SizedBox(height: AppSpacing.sp12),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.note, required this.when});

  final FieldNote note;
  final DateFormat when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final createdAt = note.createdAt;
    final stamp = createdAt == null ? '' : when.format(createdAt);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.hasAuthor) ...[
          AppAvatar(name: note.authorName, size: AvatarSize.sm),
          const SizedBox(width: AppSpacing.sp8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.hasAuthor)
                Text(
                  l10n.calendar_noteBy(note.authorName, stamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(note.text, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
