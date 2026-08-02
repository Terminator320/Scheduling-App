import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/l10n/l10n.dart';

/// One-tap job-title chips. Tapping the selected chip clears it back to
/// [JobTitle.unset] — the title is optional and must stay un-pickable-back.
///
/// The chips are a label and nothing else: they never swap, reveal or hide a
/// field, and in particular they do NOT touch the ACCESS toggle. `jobTitle` is
/// what someone does; `role` is what the app lets them see, and conflating the
/// two would make picking "Dispatcher" silently grant or revoke admin.
class JobTitleChips extends StatelessWidget {
  const JobTitleChips({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final JobTitle value;
  final ValueChanged<JobTitle> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: AppSpacing.sp8,
      runSpacing: AppSpacing.sp8,
      children: [
        for (final title in JobTitle.pickable)
          ChoiceChip(
            label: Text(jobTitleLabel(l10n, title)),
            selected: value == title,
            onSelected: (selected) =>
                onChanged(selected ? title : JobTitle.unset),
          ),
      ],
    );
  }
}
