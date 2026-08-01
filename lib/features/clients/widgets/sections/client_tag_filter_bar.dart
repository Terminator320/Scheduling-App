import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Horizontally scrolling tag chips above the clients list.
///
/// Renders nothing at all until at least one client is tagged — and nothing
/// while the tag list is loading or errored, since a filter row is an
/// enhancement and must never occupy space it can't use. Tapping the selected
/// chip clears the filter, mirroring `ClientTypeChips`.
class ClientTagFilterBar extends ConsumerWidget {
  const ClientTagFilterBar({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// Null means no tag filter is applied.
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(clientTagsProvider).value ?? const <String>[];
    if (tags.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: context.l10n.clients_filterByTag,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp16),
          itemCount: tags.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sp8),
          itemBuilder: (context, index) {
            final tag = tags[index];
            return Center(
              child: FilterChip(
                label: Text(tag),
                selected: selected == tag,
                showCheckmark: false,
                onSelected: (isSelected) => onChanged(isSelected ? tag : null),
              ),
            );
          },
        ),
      ),
    );
  }
}
