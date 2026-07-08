import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import 'authed_image.dart';
import 'scrapbook_decor.dart';

/// Renders one album page from its layout template (`event_title`,
/// `one_photo_feature`, `two_photo_story`, `four_photo_grid`) as a
/// scrapbook page: torn-paper collage corners drawn in code behind the
/// content, with photos styled as taped, white-framed prints. Each page
/// keeps a stable look via a seed derived from the page itself.
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
    final isTitle = template == 'event_title';
    final seed = page.id * 131 + page.pageNumber * 7;
    final palette = scrapbookPaletteFor(seed);
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
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ScrapbookDecorPainter(
                seed: seed,
                palette: palette,
                dense: isTitle,
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 10),
            child: Column(
              children: [
                Expanded(
                  child: isTitle
                      ? _TitleLayout(api: api, layout: page.layout)
                      : _MemoriesLayout(
                          api: api,
                          layout: page.layout,
                          palette: palette,
                        ),
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
          ),
        ],
      ),
    );
  }
}

class _TitleLayout extends StatelessWidget {
  const _TitleLayout({required this.api, required this.layout});

  final ApiClient api;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final description = layout['description'] as String? ?? '';
    final cover = layout['cover'] as Map<String, dynamic>?;
    if (cover != null) {
      final aspect = (cover['aspect_ratio'] as num?)?.toDouble() ?? 1.0;
      return LayoutBuilder(
        builder: (context, constraints) {
          // Size the cover to its own aspect ratio (so it fills the frame with
          // no letterbox), capped to a share of the page. Then center the
          // photo + title together so the whitespace above and below is even.
          final maxPhotoHeight = constraints.maxHeight * 0.58;
          final maxPhotoWidth = constraints.maxWidth * 0.86;
          var photoWidth = maxPhotoWidth;
          var photoHeight = photoWidth / (aspect <= 0 ? 1.0 : aspect);
          if (photoHeight > maxPhotoHeight) {
            photoHeight = maxPhotoHeight;
            photoWidth = photoHeight * (aspect <= 0 ? 1.0 : aspect);
          }
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: photoWidth,
                height: photoHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: const Color(0xFFEFE8D8),
                    child: AuthedImage(
                      api: api,
                      path: cover['display_url'] as String? ?? '',
                      fit: BoxFit.contain,
                      cacheWidth: 1400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Insets.lg),
              _TitleBlock(
                title: layout['title'] as String? ?? '',
                description: description,
              ),
            ],
          );
        },
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TitleBlock(
          title: layout['title'] as String? ?? '',
          description: description,
        ),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
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
          title,
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
  const _MemoriesLayout({
    required this.api,
    required this.layout,
    required this.palette,
  });

  final ApiClient api;
  final Map<String, dynamic> layout;
  final ScrapbookPalette palette;

  @override
  Widget build(BuildContext context) {
    // Orientation-aware pages carry a `rows` structure whose frames already
    // match each photo's shape.
    final rows = layout['rows'] as List<dynamic>?;
    if (rows != null && rows.isNotEmpty) {
      return _MosaicLayout(api: api, rows: rows, palette: palette);
    }
    // Fallback for pages generated before orientation-aware layouts.
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
      return _FeatureLayout(api: api, entry: entries.first, palette: palette);
    }
    if (entries.length == 2) {
      return _PairLayout(api: api, entries: entries, palette: palette);
    }
    return _GridLayout(api: api, entries: entries, palette: palette);
  }
}

/// Renders a page as stacked rows whose frames match photo orientation:
/// a landscape is a full-width band, portraits pair side by side, and the two
/// can mix on one page. Each frame uses the photo's real aspect ratio so it is
/// filled edge to edge with no letterbox and no cropping.
class _MosaicLayout extends StatelessWidget {
  const _MosaicLayout({
    required this.api,
    required this.rows,
    required this.palette,
  });

  final ApiClient api;
  final List<dynamic> rows;
  final ScrapbookPalette palette;

  @override
  Widget build(BuildContext context) {
    var total = 0;
    for (final row in rows) {
      total += ((row as Map<String, dynamic>)['memories'] as List).length;
    }
    final solo = total == 1;
    var runningIndex = 0;
    final children = <Widget>[];
    for (var r = 0; r < rows.length; r++) {
      if (r > 0) children.add(const SizedBox(height: Insets.md));
      final row = rows[r] as Map<String, dynamic>;
      final memories = [
        for (final m in row['memories'] as List<dynamic>)
          m as Map<String, dynamic>,
      ];
      children.add(Expanded(
        child: _MosaicRow(
          api: api,
          memories: memories,
          palette: palette,
          baseIndex: runningIndex,
          solo: solo,
        ),
      ));
      runningIndex += memories.length;
    }
    return Column(children: children);
  }
}

class _MosaicRow extends StatelessWidget {
  const _MosaicRow({
    required this.api,
    required this.memories,
    required this.palette,
    required this.baseIndex,
    required this.solo,
  });

  final ApiClient api;
  final List<Map<String, dynamic>> memories;
  final ScrapbookPalette palette;
  final int baseIndex;
  final bool solo;

  @override
  Widget build(BuildContext context) {
    if (memories.length == 1) {
      return _MosaicCell(
        api: api,
        entry: memories.first,
        index: baseIndex,
        palette: palette,
        solo: solo,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < memories.length; i++) ...[
          if (i > 0) const SizedBox(width: Insets.md),
          Expanded(
            child: _MosaicCell(
              api: api,
              entry: memories[i],
              index: baseIndex + i,
              palette: palette,
              solo: false,
            ),
          ),
        ],
      ],
    );
  }
}

class _MosaicCell extends StatelessWidget {
  const _MosaicCell({
    required this.api,
    required this.entry,
    required this.index,
    required this.palette,
    required this.solo,
  });

  final ApiClient api;
  final Map<String, dynamic> entry;
  final int index;
  final ScrapbookPalette palette;
  final bool solo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = entry['story_preview'] as String? ?? '';
    final ratio = (entry['aspect_ratio'] as num?)?.toDouble() ?? 1.0;
    final caption = entry['caption'] as String? ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio <= 0 ? 1.0 : ratio,
              child: _photo(api, entry, index, palette),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(
            caption,
            style:
                solo ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (solo && story.isNotEmpty) ...[
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

/// Alternating small tilts so prints look casually placed, never crooked.
const _printAngles = [-0.022, 0.018, -0.014, 0.024];

Widget _photo(
  ApiClient api,
  Map<String, dynamic> entry,
  int index,
  ScrapbookPalette palette, {
  bool thumbnail = false,
}) {
  final path =
      entry[thumbnail ? 'thumbnail_url' : 'display_url'] as String? ?? '';
  // Contain fit keeps the whole photo visible inside the frame so faces
  // are never cropped; the parchment tint fills any letterbox margins.
  return FramedPhoto(
    angle: _printAngles[index % _printAngles.length],
    tapeTint: palette.accent,
    child: ColoredBox(
      color: const Color(0xFFEFE8D8),
      // Cap decode resolution: album prints never need the full 1600px source.
      child: _sizedPhoto(api, path, thumbnail ? 500 : 1400),
    ),
  );
}

Widget _sizedPhoto(ApiClient api, String path, int cacheWidth) {
  return SizedBox.expand(
    child: AuthedImage(
      api: api,
      path: path,
      fit: BoxFit.contain,
      cacheWidth: cacheWidth,
    ),
  );
}

class _FeatureLayout extends StatelessWidget {
  const _FeatureLayout({
    required this.api,
    required this.entry,
    required this.palette,
  });

  final ApiClient api;
  final Map<String, dynamic> entry;
  final ScrapbookPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = entry['story_preview'] as String? ?? '';
    return Column(
      children: [
        Expanded(child: _photo(api, entry, 0, palette)),
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
  const _PairLayout({
    required this.api,
    required this.entries,
    required this.palette,
  });

  final ApiClient api;
  final List<Map<String, dynamic>> entries;
  final ScrapbookPalette palette;

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
                      Expanded(child: _photo(api, entries[i], i, palette)),
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
  const _GridLayout({
    required this.api,
    required this.entries,
    required this.palette,
  });

  final ApiClient api;
  final List<Map<String, dynamic>> entries;
  final ScrapbookPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cell(Map<String, dynamic> entry, int index) => Column(
          children: [
            Expanded(
                child: _photo(api, entry, index, palette, thumbnail: true)),
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
            Expanded(child: cell(entries[i], i)),
            const SizedBox(width: Insets.md),
            Expanded(
              child: i + 1 < entries.length
                  ? cell(entries[i + 1], i + 1)
                  : const SizedBox(),
            ),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}
