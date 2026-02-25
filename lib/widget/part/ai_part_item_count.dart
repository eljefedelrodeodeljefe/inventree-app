import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";

import "package:inventree/app_colors.dart";
import "package:inventree/helpers/step_sizes.dart";
import "package:inventree/l10.dart";

/// Item count section with increment/decrement buttons and a stock toggle.
class AIPartItemCount extends StatelessWidget {
  const AIPartItemCount({
    Key? key,
    required this.aiCount,
    required this.currentCount,
    required this.createStock,
    required this.onCountChanged,
    required this.onCreateStockChanged,
  }) : super(key: key);

  final int? aiCount;
  final int currentCount;
  final bool createStock;
  final ValueChanged<int> onCountChanged;
  final ValueChanged<bool> onCreateStockChanged;

  Widget _countStepButton(int delta) {
    final label = delta > 0 ? "+$delta" : "$delta";
    final isNegative = delta < 0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: () {
            onCountChanged((currentCount + delta).clamp(0, 999999));
          },
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: isNegative ? Colors.red : Colors.green,
            side: BorderSide(
              color: (isNegative ? Colors.red : Colors.green).withValues(
                alpha: 0.4,
              ),
            ),
          ),
          child: Text(label, style: TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (aiCount == null || aiCount! <= 0) {
      return SizedBox.shrink();
    }

    final steps = computeStepSizes(currentCount);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  TablerIcons.packages,
                  size: 18,
                  color: createStock ? COLOR_ACTION : COLOR_GRAY_LIGHT,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    L10().aiInitialStock,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (createStock)
                  Text(
                    "$currentCount",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                SizedBox(width: 8),
                SizedBox(
                  height: 24,
                  child: Switch(
                    value: createStock,
                    onChanged: onCreateStockChanged,
                  ),
                ),
              ],
            ),
            if (createStock) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  for (final step in steps.reversed)
                    Expanded(child: _countStepButton(-step)),
                  SizedBox(width: 12),
                  for (final step in steps)
                    Expanded(child: _countStepButton(step)),
                ],
              ),
              if (currentCount != aiCount) ...[
                SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => onCountChanged(aiCount!),
                    child: Text(
                      L10().aiResetTo(aiCount!),
                      style: TextStyle(fontSize: 12, color: COLOR_ACTION),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
