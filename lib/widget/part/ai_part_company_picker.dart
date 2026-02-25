import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";

import "package:inventree/api.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/inventree/company.dart";
import "package:inventree/l10.dart";

/// Reusable picker for manufacturer or supplier companies.
///
/// Both sections have identical structure (icon, label, selected chip,
/// search field, results list, create button) so this single widget
/// replaces the former `_buildManufacturerSection` and
/// `_buildSupplierSection` methods.
class AIPartCompanyPicker extends StatelessWidget {
  const AIPartCompanyPicker({
    Key? key,
    required this.icon,
    required this.label,
    required this.addLabel,
    required this.companyTypeLabel,
    required this.selected,
    required this.searchController,
    required this.searchResults,
    required this.isSearching,
    required this.isCreating,
    required this.isExpanded,
    required this.aiName,
    required this.searchingLabel,
    required this.noMatchLabel,
    required this.onSelected,
    required this.onCleared,
    required this.onSearch,
    required this.onCreate,
    required this.onExpand,
    this.extraFieldController,
    this.extraFieldLabel,
    this.extraFieldHint,
  }) : super(key: key);

  final IconData icon;
  final String label;
  final String addLabel;
  final String companyTypeLabel;
  final InvenTreeCompany? selected;
  final TextEditingController searchController;
  final List<InvenTreeCompany> searchResults;
  final bool isSearching;
  final bool isCreating;
  final bool isExpanded;
  final String? aiName;
  final String searchingLabel;
  final String noMatchLabel;
  final ValueChanged<InvenTreeCompany> onSelected;
  final VoidCallback onCleared;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onCreate;
  final VoidCallback onExpand;
  final TextEditingController? extraFieldController;
  final String? extraFieldLabel;
  final String? extraFieldHint;

  @override
  Widget build(BuildContext context) {
    // Collapsed state — show "Add ..." button
    if (!isExpanded) {
      return OutlinedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(addLabel),
        onPressed: onExpand,
        style: OutlinedButton.styleFrom(foregroundColor: COLOR_GRAY_LIGHT),
      );
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: COLOR_ACTION),
                SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                if (selected != null)
                  InkWell(
                    onTap: onCleared,
                    child: Icon(
                      TablerIcons.x,
                      size: 18,
                      color: COLOR_GRAY_LIGHT,
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8),
            if (selected != null) ...[
              // Selected company chip
              Chip(
                avatar: InvenTreeAPI().getThumbnail(selected!.thumbnail),
                label: Text(selected!.name),
                deleteIcon: Icon(TablerIcons.x, size: 16),
                onDeleted: onCleared,
              ),
              if (extraFieldController != null) ...[
                SizedBox(height: 8),
                TextFormField(
                  controller: extraFieldController,
                  decoration: InputDecoration(
                    labelText: extraFieldLabel,
                    hintText: extraFieldHint,
                  ),
                ),
              ],
            ] else if (isSearching) ...[
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(searchingLabel),
                ],
              ),
            ] else ...[
              // Search field
              TextFormField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: "Company name",
                  hintText: "Search or create company",
                  suffixIcon: IconButton(
                    icon: Icon(TablerIcons.search, size: 18),
                    onPressed: () {
                      final query = searchController.text.trim();
                      if (query.isNotEmpty) {
                        onSearch(query);
                      }
                    },
                  ),
                ),
                onFieldSubmitted: (value) {
                  final query = value.trim();
                  if (query.isNotEmpty) {
                    onSearch(query);
                  }
                },
              ),
              // Search results
              if (searchResults.isNotEmpty)
                ...searchResults.map(
                  (company) => InkWell(
                    onTap: () => onSelected(company),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          InvenTreeAPI().getThumbnail(company.thumbnail) ??
                              Icon(TablerIcons.building, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              company.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!company.active)
                            Container(
                              margin: EdgeInsets.only(right: 6),
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: COLOR_DANGER.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                L10().inactive,
                                style: TextStyle(
                                  color: COLOR_DANGER,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          Icon(
                            TablerIcons.chevron_right,
                            size: 18,
                            color: COLOR_GRAY_LIGHT,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (searchResults.isEmpty && aiName != null && aiName!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    noMatchLabel,
                    style: TextStyle(color: COLOR_GRAY_LIGHT, fontSize: 13),
                  ),
                ),
              // Create button
              if (aiName != null && aiName!.isNotEmpty)
                TextButton.icon(
                  icon: isCreating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(TablerIcons.plus, size: 18),
                  label: Text(
                    isCreating
                        ? L10().aiCreatingCompany
                        : L10().aiCreateCompanyAs(aiName!, companyTypeLabel),
                  ),
                  onPressed: isCreating ? null : () => onCreate(aiName!),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
