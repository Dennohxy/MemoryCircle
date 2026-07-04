import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/album_page_view.dart';

/// The flip album: a two-page spread on wide screens, single page on
/// phones. Tap the right side (or press →/space) to go forward, the left
/// side (or ←) to go back, and Escape to leave fullscreen or close.
class FlipAlbumScreen extends StatefulWidget {
  const FlipAlbumScreen({
    super.key,
    required this.api,
    required this.circleId,
    required this.album,
  });

  final ApiClient api;
  final int circleId;
  final Album album;

  @override
  State<FlipAlbumScreen> createState() => _FlipAlbumScreenState();
}

class _FlipAlbumScreenState extends State<FlipAlbumScreen> {
  late Future<Album> _future =
      widget.api.getAlbum(widget.circleId, widget.album.id);

  int _index = 0;
  bool _fullscreen = false;

  // Kept in sync during build so keyboard handlers know the page layout.
  List<AlbumPage> _pages = const [];
  bool _spread = false;

  void _retry() {
    setState(() {
      _future = widget.api.getAlbum(widget.circleId, widget.album.id);
    });
  }

  void _go(int direction) {
    if (_pages.isEmpty) return;
    final step = _spread ? 2 : 1;
    var next = _index + direction * step;
    if (next < 0) next = 0;
    if (next > _pages.length - 1) next = _pages.length - 1;
    if (next != _index) setState(() => _index = next);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        setState(() => _fullscreen = false);
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.backdrop,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: AppColors.backdrop,
              foregroundColor: AppColors.onBackdrop,
              title: Text(widget.album.title),
              actions: [
                IconButton(
                  tooltip: 'Fullscreen',
                  onPressed: () => setState(() => _fullscreen = true),
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),
      body: FutureBuilder<Album>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _darkMessage(
              theme,
              icon: Icons.cloud_off_outlined,
              title: 'We could not open this album.',
              message: '${snapshot.error}',
              actionLabel: 'Try again',
              onAction: _retry,
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            );
          }
          final pages = snapshot.data!.pages ?? const <AlbumPage>[];
          if (pages.isEmpty) {
            return _darkMessage(
              theme,
              icon: Icons.auto_stories_outlined,
              title: 'This album is empty until memories are added.',
              message:
                  'Once memories are approved, update the album pages and they will appear here.',
              actionLabel: 'Close',
              onAction: () => Navigator.of(context).maybePop(),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final spread = constraints.maxWidth >= 920;
              _pages = pages;
              _spread = spread;

              var start = _index;
              if (start > pages.length - 1) start = pages.length - 1;
              if (spread) start -= start % 2;
              final visible = [
                pages[start],
                if (spread && start + 1 < pages.length) pages[start + 1],
              ];
              final step = spread ? 2 : 1;
              final canGoBack = start > 0;
              final canGoForward = start + step <= pages.length - 1;
              final pageLabel = visible.length == 2
                  ? 'Pages ${start + 1}–${start + 2} of ${pages.length}'
                  : 'Page ${start + 1} of ${pages.length}';

              return Focus(
                autofocus: true,
                onKeyEvent: _onKeyEvent,
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _go(
                            details.localPosition.dx > constraints.maxWidth / 2
                                ? 1
                                : -1),
                        onHorizontalDragEnd: (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity < -150) _go(1);
                          if (velocity > 150) _go(-1);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(Insets.lg),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Row(
                              key: ValueKey(start),
                              children: [
                                for (final page in visible)
                                  Expanded(
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: 3 / 4,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: Insets.sm),
                                          child: AlbumPageView(
                                            api: widget.api,
                                            page: page,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Insets.sm),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous page',
                              onPressed: canGoBack ? () => _go(-1) : null,
                              icon: const Icon(Icons.chevron_left),
                              color: AppColors.onBackdrop,
                              disabledColor:
                                  AppColors.onBackdrop.withValues(alpha: 0.25),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Insets.sm),
                              child: Text(
                                pageLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.onBackdropFaded),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next page',
                              onPressed: canGoForward ? () => _go(1) : null,
                              icon: const Icon(Icons.chevron_right),
                              color: AppColors.onBackdrop,
                              disabledColor:
                                  AppColors.onBackdrop.withValues(alpha: 0.25),
                            ),
                            const SizedBox(width: Insets.lg),
                            IconButton(
                              tooltip: _fullscreen
                                  ? 'Exit fullscreen'
                                  : 'Fullscreen',
                              onPressed: () =>
                                  setState(() => _fullscreen = !_fullscreen),
                              icon: Icon(_fullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen),
                              color: AppColors.onBackdrop,
                            ),
                            if (_fullscreen)
                              IconButton(
                                tooltip: 'Close album',
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.close),
                                color: AppColors.onBackdrop,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _darkMessage(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: AppColors.onBackdropFaded),
              const SizedBox(height: Insets.md),
              Text(
                title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: AppColors.onBackdrop),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Insets.sm),
              Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.onBackdropFaded),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Insets.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
