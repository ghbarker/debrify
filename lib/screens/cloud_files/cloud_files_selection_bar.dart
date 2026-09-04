import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';

/// Multi-select chrome shared by the RD and TorBox hosts. Copied verbatim
/// from `_buildSelectionBar` on both screens (they were identical).
class CloudFilesSelectionBar extends StatelessWidget {
  const CloudFilesSelectionBar({
    super.key,
    required this.count,
    required this.isAllSelected,
    required this.onToggleSelectAll,
    required this.onDelete,
    this.deleteFocusNode,
  });

  final int count;
  final bool isAllSelected;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onDelete;
  final FocusNode? deleteFocusNode;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: app.shape.br(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onToggleSelectAll,
            child: Text(isAllSelected ? 'Deselect All' : 'Select All'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: deleteFocusNode,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style:
                FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  disabledBackgroundColor: theme.colorScheme.error.withValues(
                    alpha: 0.3,
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: app.core.tx, width: 3);
                    }
                    return null;
                  }),
                ),
          ),
        ],
      ),
    );
  }
}
