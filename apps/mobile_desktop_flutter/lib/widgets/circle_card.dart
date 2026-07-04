import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app/theme.dart';
import 'paper_card.dart';

/// A tappable card for one memory circle in the circle list.
class CircleCard extends StatelessWidget {
  const CircleCard({super.key, required this.circle, required this.onOpen});

  final Circle circle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaperCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.parchment,
            child: Text(
              circle.initials,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.deepGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(circle.name, style: theme.textTheme.titleLarge),
                if (circle.description.isNotEmpty) ...[
                  const SizedBox(height: Insets.xs),
                  Text(
                    circle.description,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.softInk),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          const Icon(Icons.chevron_right, color: AppColors.softInk),
        ],
      ),
    );
  }
}
