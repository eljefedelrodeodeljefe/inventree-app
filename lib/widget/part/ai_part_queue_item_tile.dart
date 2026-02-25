import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";

import "package:inventree/ai/ai_part_queue_service.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/l10.dart";

class AIPartQueueItemTile extends StatelessWidget {
  const AIPartQueueItemTile({
    Key? key,
    required this.item,
    required this.onTap,
    required this.onDismissed,
  }) : super(key: key);

  final AIPartQueueItem item;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 16),
        color: COLOR_DANGER,
        child: Icon(TablerIcons.trash, color: Colors.white),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            item.imageFile,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
        title: _buildTitle(),
        subtitle: _buildSubtitle(),
        trailing: _buildTrailing(),
        onTap: onTap,
      ),
    );
  }

  Widget _buildTitle() {
    switch (item.status) {
      case AIPartQueueStatus.pending:
        return Text(L10().aiQueued, style: TextStyle(color: COLOR_GRAY_LIGHT));
      case AIPartQueueStatus.analyzing:
        return Text(L10().aiAnalyzing, style: TextStyle(color: COLOR_ACTION));
      case AIPartQueueStatus.success:
        return Text(
          item.result?.name ?? L10().aiUnknown,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case AIPartQueueStatus.error:
        return Text(L10().error, style: TextStyle(color: COLOR_DANGER));
    }
  }

  Widget? _buildSubtitle() {
    switch (item.status) {
      case AIPartQueueStatus.pending:
      case AIPartQueueStatus.analyzing:
        return LinearProgressIndicator();
      case AIPartQueueStatus.success:
        final confidence = item.result?.confidence ?? 0.0;
        Color badgeColor = confidence >= 0.7
            ? COLOR_SUCCESS
            : confidence >= 0.4
            ? COLOR_WARNING
            : COLOR_DANGER;
        return Text(
          L10().aiConfidencePercent((confidence * 100).toInt()),
          style: TextStyle(color: badgeColor, fontSize: 12),
        );
      case AIPartQueueStatus.error:
        return Text(
          item.errorMessage ?? L10().aiUnknownError,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12),
        );
    }
  }

  Widget _buildTrailing() {
    switch (item.status) {
      case AIPartQueueStatus.pending:
      case AIPartQueueStatus.analyzing:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case AIPartQueueStatus.success:
        return Icon(TablerIcons.chevron_right);
      case AIPartQueueStatus.error:
        return Icon(TablerIcons.refresh, color: COLOR_DANGER);
    }
  }
}
