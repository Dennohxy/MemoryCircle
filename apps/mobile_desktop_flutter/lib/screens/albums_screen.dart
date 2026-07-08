import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/authed_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import 'bulk_add_screen.dart';
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
    final input = await showDialog<
        ({String title, String description, int? targetPhotoCount})>(
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
        targetPhotoCount: input.targetPhotoCount,
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

  /// Opens the photo picker targeted at this album so anyone who can
  /// contribute can add photos to it directly.
  Future<void> _addPhotos(Album album) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('Add to "${album.title}"')),
        body: BulkAddView(
          api: widget.api,
          circle: widget.circle,
          role: widget.role,
          targetAlbum: album,
        ),
      ),
    ));
    if (mounted) _refresh();
  }

  Future<void> _renameAlbum(Album album) async {
    final input = await showDialog<
        ({String title, String description, int? targetPhotoCount})>(
      context: context,
      builder: (_) => _EditAlbumDialog(album: album),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.updateAlbum(
        widget.circle.id,
        album.id,
        title: input.title,
        description: input.description,
        targetPhotoCount: input.targetPhotoCount,
      );
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Album details were updated.')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _arrangeAlbum(Album album) async {
    final input = await showDialog<({int? coverMemoryId, List<int> sequence})>(
      context: context,
      builder: (_) => _ArrangeAlbumDialog(
        api: widget.api,
        circle: widget.circle,
        album: album,
      ),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.updateAlbum(
        widget.circle.id,
        album.id,
        coverMemoryId: input.coverMemoryId,
        memorySequence: input.sequence,
      );
      await widget.api.generateAlbumPages(widget.circle.id, album.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Cover and photo order were updated.')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _shareAlbum(Album album) async {
    final input = await showDialog<
        ({
          String note,
          String accessType,
          DateTime? expiresAt,
          bool allowDownloads,
          bool includeCaptions,
        })>(
      context: context,
      builder: (_) => _CreateSharePackageDialog(album: album),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final package = await widget.api.createSharePackage(
        widget.circle.id,
        album.id,
        title: album.title,
        note: input.note,
        accessType: input.accessType,
        expiresAt: input.expiresAt,
        allowDownloads: input.allowDownloads,
        includeCaptions: input.includeCaptions,
      );
      if (!mounted) return;
      await Share.share(
        package.shareUrl,
        subject: 'MemoryCircle album: ${package.title}',
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Share package created. You can revoke it anytime.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _requestRemoval(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "${album.title}"?'),
        content: const Text(
            'This removes the album layout. The photos and stories stay in the '
            'circle, so an album can be made again anytime. Other album '
            'managers may need to approve before it is removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep album'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.rust),
            child: const Text('Remove album'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pending =
          await widget.api.requestAlbumRemoval(widget.circle.id, album.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(pending == null
            ? 'The album was removed.'
            : 'Waiting for the other album managers to approve.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _approveRemoval(Album album) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pending =
          await widget.api.approveAlbumRemoval(widget.circle.id, album.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(pending == null
            ? 'The album was removed.'
            : 'Your approval was recorded.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _cancelRemoval(Album album) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.cancelAlbumRemoval(widget.circle.id, album.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('The album will be kept.')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _manageSharePackages(Album album) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SharePackagesDialog(
        api: widget.api,
        circleId: widget.circle.id,
        album: album,
      ),
    );
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
                            canShare: widget.role.isOwner,
                            canAddPhotos: widget.role.canContribute,
                            currentUserId: widget.api.currentUser?.id,
                            onOpen: () => _openAlbum(album),
                            onAddPhotos: () => _addPhotos(album),
                            onRename: () => _renameAlbum(album),
                            onArrange: () => _arrangeAlbum(album),
                            onRegenerate: () => _regeneratePages(album),
                            onShare: () => _shareAlbum(album),
                            onManageShares: () => _manageSharePackages(album),
                            onRequestRemoval: () => _requestRemoval(album),
                            onApproveRemoval: () => _approveRemoval(album),
                            onCancelRemoval: () => _cancelRemoval(album),
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
    required this.canShare,
    required this.canAddPhotos,
    required this.currentUserId,
    required this.onOpen,
    required this.onAddPhotos,
    required this.onRename,
    required this.onArrange,
    required this.onRegenerate,
    required this.onShare,
    required this.onManageShares,
    required this.onRequestRemoval,
    required this.onApproveRemoval,
    required this.onCancelRemoval,
  });

  final Album album;
  final bool canManage;
  final bool canShare;
  final bool canAddPhotos;
  final int? currentUserId;
  final VoidCallback onOpen;
  final VoidCallback onAddPhotos;
  final VoidCallback onRename;
  final VoidCallback onArrange;
  final VoidCallback onRegenerate;
  final VoidCallback onShare;
  final VoidCallback onManageShares;
  final VoidCallback onRequestRemoval;
  final VoidCallback onApproveRemoval;
  final VoidCallback onCancelRemoval;

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
                      const SizedBox(height: Insets.sm),
                      Text(
                        'Planned for ${album.targetPhotoCount} photos',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.onBackdropFaded),
                      ),
                      const Spacer(),
                      if (album.isPendingRemoval)
                        _removalBanner(theme)
                      else
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
                            const Spacer(),
                            if (canAddPhotos)
                              IconButton(
                                tooltip: 'Add photos to this album',
                                onPressed: onAddPhotos,
                                icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 20,
                                    color: AppColors.gold),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if ((canManage || canShare) && !album.isPendingRemoval)
                Positioned(
                  top: 4,
                  right: 4,
                  child: PopupMenuButton<String>(
                    tooltip: 'Album options',
                    iconColor: AppColors.onBackdropFaded,
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          onRename();
                        case 'regenerate':
                          onRegenerate();
                        case 'arrange':
                          onArrange();
                        case 'remove':
                          onRequestRemoval();
                        case 'share':
                          onShare();
                        case 'shares':
                          onManageShares();
                      }
                    },
                    itemBuilder: (_) => [
                      if (canManage) ...const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Edit name and note'),
                        ),
                        PopupMenuItem(
                          value: 'arrange',
                          child: Text('Choose cover and order'),
                        ),
                        PopupMenuItem(
                          value: 'regenerate',
                          child: Text('Update pages from approved memories'),
                        ),
                      ],
                      if (canShare) ...const [
                        PopupMenuItem(
                          value: 'share',
                          child: Text('Create share package'),
                        ),
                        PopupMenuItem(
                          value: 'shares',
                          child: Text('Manage share packages'),
                        ),
                      ],
                      if (canManage) ...const [
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove album…'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _removalBanner(ThemeData theme) {
    final removal = album.removal;
    final alreadyVoted = removal?.hasVoted(currentUserId) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hourglass_top, size: 16, color: AppColors.gold),
            const SizedBox(width: Insets.xs),
            Expanded(
              child: Text(
                removal == null
                    ? 'Waiting to be removed'
                    : 'Waiting to be removed · ${removal.approvalsHave} of ${removal.approvalsNeeded} approved',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.onBackdropFaded),
              ),
            ),
          ],
        ),
        if (canManage) ...[
          const SizedBox(height: Insets.xs),
          Row(
            children: [
              if (!alreadyVoted)
                TextButton(
                  onPressed: onApproveRemoval,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.rust,
                    padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Approve'),
                ),
              TextButton(
                onPressed: onCancelRemoval,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Keep'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CreateSharePackageDialog extends StatefulWidget {
  const _CreateSharePackageDialog({required this.album});

  final Album album;

  @override
  State<_CreateSharePackageDialog> createState() =>
      _CreateSharePackageDialogState();
}

class _CreateSharePackageDialogState extends State<_CreateSharePackageDialog> {
  final _noteController = TextEditingController();
  String _accessType = 'expires_at';
  bool _allowDownloads = false;
  bool _includeCaptions = true;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  DateTime? get _expiresAt => _accessType == 'expires_at'
      ? DateTime.now().add(const Duration(days: 30))
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Create share package'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Only "${widget.album.title}" will be shared. People with the link can view it without signing in.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.softInk),
              ),
              const SizedBox(height: Insets.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'expires_at',
                    label: Text('30 days'),
                    icon: Icon(Icons.schedule_outlined),
                  ),
                  ButtonSegment(
                    value: 'expires_after_view',
                    label: Text('One view'),
                    icon: Icon(Icons.visibility_outlined),
                  ),
                  ButtonSegment(
                    value: 'saved',
                    label: Text('Saved'),
                    icon: Icon(Icons.bookmark_border),
                  ),
                ],
                selected: {_accessType},
                onSelectionChanged: (value) =>
                    setState(() => _accessType = value.first),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 3,
                decoration: appInput(
                  'Optional note',
                  hint: 'For example, "Photos from the reunion."',
                ),
              ),
              const SizedBox(height: Insets.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeCaptions,
                title: const Text('Include captions and stories'),
                onChanged: (value) => setState(() => _includeCaptions = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowDownloads,
                title: const Text('Allow downloads'),
                subtitle: const Text('Off is safer for most family shares.'),
                onChanged: (value) => setState(() => _allowDownloads = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            note: _noteController.text.trim(),
            accessType: _accessType,
            expiresAt: _expiresAt,
            allowDownloads: _allowDownloads,
            includeCaptions: _includeCaptions,
          )),
          child: const Text('Create link'),
        ),
      ],
    );
  }
}

class _SharePackagesDialog extends StatefulWidget {
  const _SharePackagesDialog({
    required this.api,
    required this.circleId,
    required this.album,
  });

  final ApiClient api;
  final int circleId;
  final Album album;

  @override
  State<_SharePackagesDialog> createState() => _SharePackagesDialogState();
}

class _SharePackagesDialogState extends State<_SharePackagesDialog> {
  late Future<List<SharePackage>> _future = widget.api.listSharePackages(
    widget.circleId,
    widget.album.id,
  );

  void _refresh() {
    setState(() {
      _future = widget.api.listSharePackages(widget.circleId, widget.album.id);
    });
  }

  Future<void> _revoke(SharePackage package) async {
    try {
      await widget.api.revokeSharePackage(
        widget.circleId,
        widget.album.id,
        package.id,
      );
      _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share packages'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<SharePackage>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(
                  message: '${snapshot.error}', onRetry: _refresh);
            }
            if (!snapshot.hasData) {
              return const LoadingState(message: 'Finding share packages…');
            }
            final packages = snapshot.data!;
            if (packages.isEmpty) {
              return const EmptyState(
                icon: Icons.ios_share_outlined,
                title: 'No share packages yet',
                message:
                    'Create a package when you are ready to share this album outside the circle.',
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: packages.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final package = packages[index];
                  final expires = package.expiresAt == null
                      ? ''
                      : ' · Expires ${formatFriendlyDate(package.expiresAt)}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(package.title),
                    subtitle: Text('${package.statusLabel}$expires'),
                    trailing: Wrap(
                      spacing: Insets.xs,
                      children: [
                        IconButton(
                          tooltip: 'Share link',
                          icon: const Icon(Icons.ios_share_outlined),
                          onPressed: package.status == 'active'
                              ? () => Share.share(
                                    package.shareUrl,
                                    subject:
                                        'MemoryCircle album: ${package.title}',
                                  )
                              : null,
                        ),
                        IconButton(
                          tooltip: 'Revoke access',
                          icon: const Icon(Icons.link_off_outlined),
                          onPressed: package.status == 'active'
                              ? () => _revoke(package)
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EditAlbumDialog extends StatefulWidget {
  const _EditAlbumDialog({required this.album});

  final Album album;

  @override
  State<_EditAlbumDialog> createState() => _EditAlbumDialogState();
}

class _ArrangeAlbumDialog extends StatefulWidget {
  const _ArrangeAlbumDialog({
    required this.api,
    required this.circle,
    required this.album,
  });

  final ApiClient api;
  final Circle circle;
  final Album album;

  @override
  State<_ArrangeAlbumDialog> createState() => _ArrangeAlbumDialogState();
}

class _ArrangeAlbumDialogState extends State<_ArrangeAlbumDialog> {
  late Future<List<Memory>> _future =
      widget.api.listMemories(widget.circle.id, status: 'approved');
  final List<Memory> _ordered = [];
  int? _coverMemoryId;
  bool _initialized = false;

  void _initialize(List<Memory> memories) {
    if (_initialized) return;
    final byId = {for (final memory in memories) memory.id: memory};
    for (final memoryId in widget.album.memorySequence) {
      final memory = byId[memoryId];
      if (memory != null) _ordered.add(memory);
    }
    for (final memory in memories) {
      if (!_ordered.any((item) => item.id == memory.id)) _ordered.add(memory);
    }
    _coverMemoryId = widget.album.coverMemoryId ??
        (_ordered.isEmpty ? null : _ordered.first.id);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose cover and order'),
      content: SizedBox(
        width: 520,
        height: 560,
        child: FutureBuilder<List<Memory>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(
                message: '${snapshot.error}',
                onRetry: () => setState(() {
                  _initialized = false;
                  _ordered.clear();
                  _future = widget.api
                      .listMemories(widget.circle.id, status: 'approved');
                }),
              );
            }
            if (!snapshot.hasData) {
              return const LoadingState(message: 'Loading approved photos...');
            }
            final memories = snapshot.data!;
            if (memories.isEmpty) {
              return const EmptyState(
                icon: Icons.photo_outlined,
                title: 'No approved photos yet',
                message:
                    'Once the family has approved photos, you can choose the cover and order here.',
              );
            }
            _initialize(memories);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _coverMemoryId,
                  decoration: appInput('Cover photo'),
                  items: [
                    for (final memory in _ordered)
                      DropdownMenuItem(
                        value: memory.id,
                        child: Text(
                          memory.caption.isEmpty
                              ? 'Untitled photo'
                              : memory.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _coverMemoryId = value),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  'Drag photos into the order you want them to appear.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.softInk),
                ),
                const SizedBox(height: Insets.sm),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _ordered.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _ordered.removeAt(oldIndex);
                        _ordered.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final memory = _ordered[index];
                      return ListTile(
                        key: ValueKey(memory.id),
                        leading: SizedBox(
                          width: 52,
                          height: 52,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: AuthedImage(
                              api: widget.api,
                              path: memory.asset?.thumbnailUrl ?? '',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        title: Text(memory.caption.isEmpty
                            ? 'Untitled photo'
                            : memory.caption),
                        subtitle: Text(memory.metaLine),
                        trailing: const Icon(Icons.drag_handle),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _ordered.isEmpty
              ? null
              : () => Navigator.of(context).pop((
                    coverMemoryId: _coverMemoryId,
                    sequence: [for (final memory in _ordered) memory.id],
                  )),
          child: const Text('Save order'),
        ),
      ],
    );
  }
}

class _EditAlbumDialogState extends State<_EditAlbumDialog> {
  late final _titleController = TextEditingController(text: widget.album.title);
  late final _descriptionController =
      TextEditingController(text: widget.album.description);
  late final _targetController =
      TextEditingController(text: '${widget.album.targetPhotoCount}');

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _titleController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Edit album'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: appInput('Album title'),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 3,
              decoration: appInput('A short note for the cover (optional)'),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              decoration: appInput(
                'Planned number of photos',
                helper: widget.album.maxPhotoCount == null
                    ? 'Used when pages are generated.'
                    : 'Family maximum: ${widget.album.maxPhotoCount} photos '
                        '(12 per member).',
              ),
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
          onPressed: canSave
              ? () => Navigator.of(context).pop((
                    title: _titleController.text.trim(),
                    description: _descriptionController.text.trim(),
                    targetPhotoCount:
                        int.tryParse(_targetController.text.trim()),
                  ))
              : null,
          child: const Text('Save changes'),
        ),
      ],
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
  final _targetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetController.dispose();
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
            const SizedBox(height: Insets.md),
            TextField(
              controller: _targetController,
              keyboardType: TextInputType.number,
              decoration: appInput(
                'Planned number of photos (optional)',
                helper:
                    'Leave empty for the family maximum: 12 photos per member.',
              ),
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
                    targetPhotoCount:
                        int.tryParse(_targetController.text.trim()),
                  ))
              : null,
          child: const Text('Create album'),
        ),
      ],
    );
  }
}
