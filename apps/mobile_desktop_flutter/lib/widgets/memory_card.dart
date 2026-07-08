import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import 'authed_image.dart';
import 'paper_card.dart';

/// A memory in a list: thumbnail, caption, event/date, and who sent it.
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.api,
    required this.memory,
    this.sentBy,
    this.onTap,
  });

  final ApiClient api;
  final Memory memory;
  final String? sentBy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaperCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.sm + Insets.xs),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 84,
              height: 84,
              child: memory.asset == null
                  ? const ColoredBox(
                      color: Color(0xFFEFE7D7),
                      child:
                          Icon(Icons.photo_outlined, color: AppColors.softInk),
                    )
                  : AuthedImage(
                      api: api,
                      path: memory.asset!.thumbnailUrl,
                      cacheWidth: 200,
                    ),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.caption.isEmpty ? 'Untitled memory' : memory.caption,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (memory.metaLine.isNotEmpty) ...[
                  const SizedBox(height: Insets.xs),
                  Text(
                    memory.metaLine,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.softInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (sentBy != null && sentBy!.isNotEmpty) ...[
                  const SizedBox(height: Insets.xs),
                  Text(
                    'Sent by $sentBy',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.softInk),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: AppColors.softInk),
        ],
      ),
    );
  }
}
