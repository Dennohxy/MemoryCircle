import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import 'authed_image.dart';

/// Renders one album page from its layout template:
/// `event_title`, `one_photo_feature`, `two_photo_story`, `four_photo_grid`.
class AlbumPageView extends StatelessWidget {
  const AlbumPageView({
    super.key,
    required this.api,
    required this.page,
    this.showPageNumber = true,
  });

  final ApiClient api;
  final AlbumPage page;
  final bool showPageNumber;

  @override
  Widget build(BuildContext context) {
    final template = page.layout['template'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEF), Color(0xFFF6EDDA)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8DCC2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 10),
      child: Column(
        children: [
          Expanded(
            child: template == 'event_title'
                ? _TitleLayout(layout: page.layout)
                : _MemoriesLayout(api: api, layout: page.layout),
          ),
          if (showPageNumber)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                '${page.pageNumber}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.softInk),
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleLayout extends StatelessWidget {
  const _TitleLayout({required this.layout});

  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = layout['description'] as String? ?? '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'MEMORY ALBUM',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.gold,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Insets.md),
        Text(
          layout['title'] as String? ?? '',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Insets.md),
        Container(width: 56, height: 2, color: AppColors.gold),
        if (description.isNotEmpty) ...[
          const SizedBox(height: Insets.md),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.softInk,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _MemoriesLayout extends StatelessWidget {
  const _MemoriesLayout({required this.api, required this.layout});

  final ApiClient api;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final item in layout['memories'] as List<dynamic>? ?? const [])
        item as Map<String, dynamic>,
    ];
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'This page is empty.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.softInk),
        ),
      );
    }
    if (entries.length == 1) {
      return _FeatureLayout(api: api, entry: entries.first);
    }
    if (entries.length == 2) return _PairLayout(api: api, entries: entries);
    return _GridLayout(api: api, entries: entries);
  }
}

Widget _photo(ApiClient api, Map<String, dynamic> entry,
    {bool thumbnail = false}) {
  final path =
      entry[thumbnail ? 'thumbnail_url' : 'display_url'] as String? ?? '';
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.expand(child: AuthedImage(api: api, path: path)),
  );
}

class _FeatureLayout extends StatelessWidget {
  const _FeatureLayout({required this.api, required this.entry});

  final ApiClient api;
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = entry['story_preview'] as String? ?? '';
    return Column(
      children: [
        Expanded(child: _photo(api, entry)),
        const SizedBox(height: Insets.sm + Insets.xs),
        Text(
          entry['caption'] as String? ?? '',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (story.isNotEmpty) ...[
          const SizedBox(height: Insets.xs),
          Text(
            story,
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _PairLayout extends StatelessWidget {
  const _PairLayout({required this.api, required this.entries});

  final ApiClient api;
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = entries.first['story_preview'] as String? ?? '';
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _photo(api, entries[i])),
                      const SizedBox(height: Insets.sm),
                      Text(
                        entries[i]['caption'] as String? ?? '',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (story.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(
            story,
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _GridLayout extends StatelessWidget {
  const _GridLayout({required this.api, required this.entries});

  final ApiClient api;
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cell(Map<String, dynamic> entry) => Column(
          children: [
            Expanded(child: _photo(api, entry, thumbnail: true)),
            const SizedBox(height: Insets.xs),
            Text(
              entry['caption'] as String? ?? '',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );

    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: Insets.md));
      rows.add(Expanded(
        child: Row(
          children: [
            Expanded(child: cell(entries[i])),
            const SizedBox(width: Insets.md),
            Expanded(
              child: i + 1 < entries.length
                  ? cell(entries[i + 1])
                  : const SizedBox(),
            ),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}
