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

  /// When non-null, shows "Add client" affordance; null shows plain no-results text.
  final VoidCallback? onAddNew;

  /// Max dropdown height (about 5 dense tiles); list scrolls to keep all 25 results reachable.
  static const double _maxDropdownHeight = 280;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showAddNew =
        onAddNew != null &&
        !isSearching &&
        selectedClient == null &&
        controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
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
                    // Typed-but-unselected: "x" clears query and results; empty shows search icon.
                    : ClearTextButton(
                        controller: controller,
                        onCleared: () => onChanged(''),
                        placeholder: const Icon(Icons.search, size: 18),
                      ),
              ),

          onChanged: onChanged,
          onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        if (results.isNotEmpty)
          Container(
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
                if (index == results.length) {
                  return _addNewClientTile(context);
                }
                final client = results[index];
                final String subtitleText;
                if (client.phone.trim().isNotEmpty) {
                  subtitleText = client.phone;
                } else if (client.email.trim().isNotEmpty) {
                  subtitleText = client.email;
                } else {
                  subtitleText = client.address;
                }
                return ListTile(
                  dense: true,
                  title: Text(
                    client.displayName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    subtitleText,
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
          ),

        if (results.isEmpty &&
            !isSearching &&
            controller.text.trim().isNotEmpty &&
            selectedClient == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sp8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.clients_noClientsFound,
                  style: TextStyle(
                    fontSize: 13,
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
          ),
      ],
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
