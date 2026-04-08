import 'package:flutter/material.dart';
import '../../models/client_record.dart';
import '../../utils/calendar_utils/form_widgets.dart';

class ClientSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ClientRecord? selectedClient;
  final List<ClientRecord> results;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final ValueChanged<ClientRecord> onSelect;
  final VoidCallback onClear;
  final String? errorText;

  const ClientSearchField({
    super.key,
    required this.controller,
    required this.selectedClient,
    required this.results,
    required this.isSearching,
    required this.onChanged,
    required this.onSelect,
    required this.onClear,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          readOnly: selectedClient != null,
          decoration:
              formInputDecoration(
                context,
                "Search by name or phone number",
              ).copyWith(
                errorText: errorText,
                suffixIcon: selectedClient != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: onClear,
                      )
                    : isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search, size: 18),
              ),

          onChanged: onChanged,
        ),
        if (results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: results
                  .map(
                    (client) => ListTile(
                      dense: true,
                      title: Text(
                        client.displayName,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        client.phone,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      onTap: () => onSelect(client),
                    ),
                  )
                  .toList(),
            ),
          ),

        if (results.isEmpty &&
            !isSearching &&
            controller.text.trim().isNotEmpty &&
            selectedClient == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "No clients found",
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
