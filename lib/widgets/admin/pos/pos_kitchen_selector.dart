import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_strings.dart';
import '../../../l10n/strings_pos.dart';
import '../../../models/kitchen.dart';
import '../../../providers/locale_provider.dart';

class PosKitchenSelector extends StatelessWidget {
  const PosKitchenSelector({
    super.key,
    required this.kitchens,
    required this.selectedId,
    required this.autoSuggestedId,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Kitchen> kitchens;
  final String? selectedId;
  final String? autoSuggestedId;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (kitchens.isEmpty) return const SizedBox.shrink();

    final locale = context.watch<LocaleProvider>().localeCode;
    final s = AppStrings.of(context);
    final effectiveSelected = selectedId ?? autoSuggestedId ?? kitchens.first.id;
    final isAuto = effectiveSelected == autoSuggestedId;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: s.posTargetKitchen,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        helperText: isAuto ? s.posKitchenAutoSuggested : s.posKitchenManualOverride,
        helperStyle: TextStyle(
          fontSize: 10,
          color: isAuto ? Colors.green.shade700 : Colors.orange.shade800,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveSelected,
          isExpanded: true,
          onChanged: enabled
              ? (id) {
                  if (id != null) onChanged(id);
                }
              : null,
          items: kitchens.map((kitchen) {
            final label = kitchen.localizedName(locale);
            return DropdownMenuItem(
              value: kitchen.id,
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  if (kitchen.id == autoSuggestedId)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.auto,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
