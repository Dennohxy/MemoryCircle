import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import 'flip_album_screen.dart';

/// Albums shown as covers, with creation from approved memories.
class AlbumsView extends StatefulWidget {
  const AlbumsView({
    super.key,
    required this.api,
    required this.circle,
    required this.role,
  });

  final ApiClient api;
  final Circle circle;
  final CircleRole role;

  @override
  State<AlbumsView> createState() => _AlbumsViewState();
}

class _AlbumsViewState extends State<AlbumsView> {
  late Future<List<Album>> _albums = widget.api.listAlbums(widget.circle.id);
  bool _creating = false;

  void _refresh() =>
      setState(() => _albums = widget.api.listAlbums(widget.circle.id));

  Future<void> _openAlbum(Album album) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlipAlbumScreen(
        api: widget.api,
        circleId: widget.circle.id,
        album: album,
      ),
    ));
  }

  Future<void> _createAlbum() async {
    final input = await showDialog<({String title, String description})>(
      context: context,
      builder: (_) => const _CreateAlbumDialog(),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creating = true);
    try {
      final album = await widget.api.createAlbum(
        widget.circle.id,
        title: input.title,
        description: input.description,
      );
      await widget.api.generateAlbumPages(widget.circle.id, album.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(
        content: Text('Your album is ready to flip through.'),
      ));
      await _openAlbum(album);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _regeneratePages(Album album) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.generateAlbumPages(widget.circle.id, album.id);
      messenger.showSnackBar(const SnackBar(
        content: Text('Album pages were updated from approved memories.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Album>>(
      future: _albums,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(message: '${snapshot.error}', onRetry: _refresh);
        }
        if (!snapshot.hasData) {
          return const LoadingState(message: 'Finding your albums…');
        }
        final albums = snapshot.data!;
        if (albums.isEmpty) {
          return EmptyState(
            icon: Icons.auto_stories_outlined,
            title: 'No albums yet',
            message: widget.role.canReview
                ? 'Create the first album from the memories your family has approved.'
                : 'Once a reviewer creates an album, it will appear here.',
            actionLabel: widget.role.canReview
                ? 'Create album from approved memories'
                : null,
            onAction: widget.role.canReview ? _createAlbum : null,
          );
        }
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.role.canReview) ...[
                      FilledButton.tonalIcon(
                        onPressed: _creating ? null : _createAlbum,
                        icon: const Icon(Icons.add),
                        label:
                            const Text('Create album from approved memories'),
                      ),
                      if (_creating) ...[
                        const SizedBox(height: Insets.sm),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: Insets.md),
                    ],
                    Wrap(
                      spacing: Insets.md,
                      runSpacing: Insets.md,
                      children: [
                        for (final album in albums)
                          _AlbumCover(
                            album: album,
                            canManage: widget.role.canReview,
                            onOpen: () => _openAlbum(album),
                            onRegenerate: () => _regeneratePages(album),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({
    required this.album,
    required this.canManage,
    required this.onOpen,
    required this.onRegenerate,
  });

  final Album album;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 236,
      height: 300,
      child: Material(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.55)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(Insets.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MEMORY ALBUM',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.onBackdropFaded,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: Insets.md),
                      Text(
                        album.title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: AppColors.onBackdrop),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (album.description.isNotEmpty) ...[
                        const SizedBox(height: Insets.sm),
                        Text(
                          album.description,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.onBackdropFaded),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            'Open album',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.gold),
                          ),
                          const SizedBox(width: Insets.xs),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: AppColors.gold),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (canManage)
                Positioned(
                  top: 4,
                  right: 4,
                  child: PopupMenuButton<String>(
                    tooltip: 'Album options',
                    iconColor: AppColors.onBackdropFaded,
                    onSelected: (value) {
                      if (value == 'regenerate') onRegenerate();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'regenerate',
                        child: Text('Update pages from approved memories'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateAlbumDialog extends StatefulWidget {
  const _CreateAlbumDialog();

  @override
  State<_CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends State<_CreateAlbumDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCreate = _titleController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Create an album'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We will arrange all the approved memories into pages for you.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: appInput('Album title',
                  hint: 'For example, "Family Highlights 2024"'),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 3,
              decoration: appInput('A short note for the cover (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canCreate
              ? () => Navigator.of(context).pop((
                    title: _titleController.text.trim(),
                    description: _descriptionController.text.trim(),
                  ))
              : null,
          child: const Text('Create album'),
        ),
      ],
    );
  }
}
