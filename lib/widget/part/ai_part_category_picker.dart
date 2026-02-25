import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";
import "package:one_context/one_context.dart";

import "package:inventree/app_colors.dart";
import "package:inventree/l10.dart";

/// Category picker dropdown that shows a dialog with parent category,
/// AI-suggested category, and sub-categories.
class AIPartCategoryPicker extends StatelessWidget {
  const AIPartCategoryPicker({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.pendingCategoryCreation,
    required this.categorySuggestion,
    this.parentCategoryId,
    this.parentCategoryName,
    this.subCategories,
    required this.onPicked,
  }) : super(key: key);

  final int? categoryId;
  final String? categoryName;
  final String? pendingCategoryCreation;
  final String? categorySuggestion;
  final int? parentCategoryId;
  final String? parentCategoryName;
  final Map<String, int>? subCategories;
  final void Function(int? id, String? name, String? pending) onPicked;

  void _showCategoryPicker() {
    void pick({int? id, String? name, String? pending}) {
      OneContext().popDialog();
      onPicked(id, name, pending);
    }

    final usedIds = <int>{};
    final children = <Widget>[];

    // 1. Parent category
    if (parentCategoryName != null && parentCategoryName!.isNotEmpty) {
      final parentId = parentCategoryId;
      if (parentId != null) usedIds.add(parentId);
      children.add(
        GestureDetector(
          onTap: () => pick(id: parentId, name: parentCategoryName),
          child: ListTile(
            leading: Icon(TablerIcons.folder, color: COLOR_ACTION),
            title: Text(parentCategoryName!),
            trailing:
                (categoryId == parentId && pendingCategoryCreation == null)
                ? Icon(TablerIcons.check, size: 18, color: COLOR_SUCCESS)
                : null,
          ),
        ),
      );
    }

    // 2. AI suggestion — only if truly new
    if (categorySuggestion != null && categorySuggestion!.isNotEmpty) {
      final matchesParent =
          categorySuggestion!.toLowerCase() ==
          (parentCategoryName ?? "").toLowerCase();
      final matchesSub =
          subCategories?.keys.any(
            (k) => k.toLowerCase() == categorySuggestion!.toLowerCase(),
          ) ??
          false;

      if (!matchesSub && !matchesParent) {
        children.add(Divider(height: 1));
        children.add(
          GestureDetector(
            onTap: () => pick(
              id: parentCategoryId,
              name: categorySuggestion,
              pending: categorySuggestion,
            ),
            child: ListTile(
              leading: Icon(TablerIcons.sparkles, color: COLOR_WARNING),
              title: Text(
                "$categorySuggestion (new)",
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              trailing: (pendingCategoryCreation == categorySuggestion)
                  ? Icon(TablerIcons.check, size: 18, color: COLOR_SUCCESS)
                  : null,
            ),
          ),
        );
      }
    }

    // 3. Sub-categories
    if (subCategories != null && subCategories!.isNotEmpty) {
      children.add(Divider(height: 1));
      for (final entry in subCategories!.entries) {
        if (usedIds.contains(entry.value)) continue;
        children.add(
          GestureDetector(
            onTap: () => pick(id: entry.value, name: entry.key),
            child: ListTile(
              leading: Icon(TablerIcons.folder, color: COLOR_GRAY_LIGHT),
              title: Text(entry.key),
              trailing:
                  (categoryId == entry.value && pendingCategoryCreation == null)
                  ? Icon(TablerIcons.check, size: 18, color: COLOR_SUCCESS)
                  : null,
            ),
          ),
        );
      }
    }

    OneContext().showDialog(
      builder: (_) => AlertDialog(
        title: Text(L10().aiSelectCategory),
        content: SingleChildScrollView(child: Column(children: children)),
        actions: [
          TextButton(
            child: Text(L10().cancel),
            onPressed: () => OneContext().popDialog(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayName =
        categoryName ?? parentCategoryName ?? L10().aiNoCategory;
    if (pendingCategoryCreation != null) {
      displayName = "$pendingCategoryCreation (new)";
    }

    return Card(
      child: InkWell(
        onTap: _showCategoryPicker,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(TablerIcons.folder, color: COLOR_ACTION, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(TablerIcons.chevron_down, size: 18, color: COLOR_GRAY_LIGHT),
            ],
          ),
        ),
      ),
    );
  }
}
