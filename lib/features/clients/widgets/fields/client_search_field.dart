import 'package:flutter/material.dart';
import 'package:scheduling/core/adaptive/adaptive_progress_indicator.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

class ClientSearchField extends StatelessWidget {
  const ClientSearchField({
    required this.controller,
    required this.selectedClient,
    required this.results,
    required this.isSearching,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
    super.key,
    this.errorText,
    this.onAddNew,
  });
  final TextEditingController controller;
  final ClientRecord? selectedClient;
  final List<ClientRecord> results;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final ValueChanged<ClientRecord> onSelect;
  final VoidCallback onClear;
  final String? errorText;

  /// When non-null, shows an "Add client" affordance. When null, just shows plain
  /// no-results text.
  final VoidCallback? onAddNew;

  /// Max dropdown height, about 5 dense tiles. The list scrolls so all 25 results
  /// stay reachable.
  static const double _maxDropdownHeight = 280;

  @override
  Widget build(BuildContext context) {
    final showAddNew =
        onAddNew != null &&
        !isSearching &&
        selectedClient == null &&
        controller.text.trim().isNotEmpty;
    final showNoResults =
        results.isEmpty &&
        !isSearching &&
        controller.text.trim().isNotEmpty &&
        selectedClient == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _searchInput(context),
        if (results.isNotEmpty) _resultsDropdown(context, showAddNew),
        if (showNoResults) _noResults(context, showAddNew),
      ],
    );
  }

  Widget _searchInput(BuildContext context) => TextFormField(
    controller: controller,
    readOnly: selectedClient != null,
    textInputAction: TextInputAction.search,
    decoration:
        formInputDecoration(
          context,
          context.l10n.clients_searchByNameBusinessPhoneEmailAddress,
        ).copyWith(
          errorText: errorText,
          suffixIcon: selectedClient != null
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: context.l10n.common_clearText,
                  onPressed: onClear,
                )
              : isSearching
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.sp12),
                  child: AdaptiveProgressIndicator(size: 16),
                )
              // Typed but not yet selected — an "x" to clear the query and
              // results, or the search icon if the field's empty.
              : ClearTextButton(
                  controller: controller,
                  onCleared: () => onChanged(''),
                  placeholder: const Icon(Icons.search, size: 18),
                ),
        ),
    onChanged: onChanged,
    onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
  );

  Widget _resultsDropdown(BuildContext context, bool showAddNew) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sp4),
      constraints: const BoxConstraints(maxHeight: _maxDropdownHeight),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length + (showAddNew ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == results.length) return _addNewClientTile(context);
          final client = results[index];
          return ListTile(
            dense: true,
            title: Text(
              client.displayName,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Text(
              _subtitleFor(client),
              style: Theme.of(context).textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              FocusScope.of(context).unfocus();
              onSelect(client);
            },
          );
        },
      ),
    );
  }

  /// The one identifying line under a result, in falling order of usefulness
  /// for telling two clients apart.
  static String _subtitleFor(ClientRecord client) {
    if (client.phone.trim().isNotEmpty) return client.phone;
    if (client.email.trim().isNotEmpty) return client.email;
    return client.address;
  }

  Widget _noResults(BuildContext context, bool showAddNew) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.clients_noClientsFound,
            style: TextStyle(
              fontSize: 13,
              // Not an error when there is something to do about it.
              color: showAddNew ? scheme.onSurfaceVariant : scheme.error,
            ),
          ),
          if (showAddNew) ...[
            const SizedBox(height: AppSpacing.sp4),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _addNewClientTile(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addNewClientTile(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(Icons.person_add_alt_1, size: 20, color: scheme.primary),
      title: Text(
        context.l10n.clients_addNamedClient(controller.text.trim()),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        FocusScope.of(context).unfocus();
        onAddNew!();
      },
    );
  }
}
