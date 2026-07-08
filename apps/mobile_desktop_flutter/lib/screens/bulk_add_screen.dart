import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/paper_card.dart';
import 'flip_album_screen.dart';

/// Brings a whole phone album into the circle at once.
///
/// Every selected photo is fingerprinted locally first; photos that already
/// exist in the circle are linked instead of being uploaded again, so no
/// duplicate copies are ever stored. Captions and stories can be filled in
/// later from Review Memories.
class BulkAddView extends StatefulWidget {
  const BulkAddView({
    super.key,
    required this.api,
    required this.circle,
    required this.role,
    this.targetAlbum,
  });

  final ApiClient api;
  final Circle circle;
  final CircleRole role;

  /// When set, photos are added to this specific album instead of creating
  /// or refreshing all albums.
  final Album? targetAlbum;

  @override
  State<BulkAddView> createState() => _BulkAddViewState();
}

enum _PhotoState { waiting, working, added, alreadyHere, failed }

class _BulkPhoto {
  _BulkPhoto(this.file);

  final PlatformFile file;
  String? hash;
  _PhotoState state = _PhotoState.waiting;
  String? error;
}

class _BulkAddViewState extends State<BulkAddView> {
  final _albumTitleController = TextEditingController();
  final List<_BulkPhoto> _photos = [];

  bool _running = false;
  bool _finished = false;
  int _processed = 0;
  int _added = 0;
  int _reused = 0;
  int _failed = 0;
  String? _error;
  Album? _openableAlbum;

  @override
  void dispose() {
    _albumTitleController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() {
      _photos
        ..clear()
        ..addAll(result.files.map(_BulkPhoto.new));
      _finished = false;
      _processed = _added = _reused = _failed = 0;
      _error = null;
      _openableAlbum = null;
    });
  }

  /// "IMG_2024-01_beach-day.jpg" -> "IMG 2024 01 beach day"
  Future<void> _run() async {
    if (_photos.isEmpty || _running) return;
    final circleId = widget.circle.id;
    setState(() {
      _running = true;
      _error = null;
      _processed = _added = _reused = _failed = 0;
      _finished = false;
    });
    try {
      // Fingerprint locally, then ask the circle which photos it already
      // has, so those are linked instead of uploaded again.
      for (final photo in _photos) {
        final bytes = photo.file.bytes;
        if (bytes != null) photo.hash = sha256.convert(bytes).toString();
      }
      final hashes = [
        for (final photo in _photos)
          if (photo.hash != null) photo.hash!,
      ];
      final matches = hashes.isEmpty
          ? <String, PhotoAsset>{}
          : await widget.api.matchPhotos(circleId, hashes);
      final existing = await widget.api.listMemories(circleId);
      final memoryByAsset = {
        for (final memory in existing) memory.assetId: memory,
      };

      for (final photo in _photos) {
        if (!mounted) return;
        setState(() => photo.state = _PhotoState.working);
        try {
          final matched = photo.hash == null ? null : matches[photo.hash];
          final asset =
              matched ?? await widget.api.uploadPhoto(circleId, photo.file);
          var memory = memoryByAsset[asset.id];
          // Leave the caption empty rather than inventing one from the camera
          // filename; the album shows the photo's date until someone adds a
          // real caption.
          memory ??= await widget.api.createMemory(
            circleId,
            assetId: asset.id,
            caption: '',
          );
          memoryByAsset[asset.id] = memory;
          if (!mounted) return;
          setState(() {
            photo.state =
                matched == null ? _PhotoState.added : _PhotoState.alreadyHere;
            if (matched == null) {
              _added++;
            } else {
              _reused++;
            }
          });
        } on ApiException catch (error) {
          if (!mounted) return;
          setState(() {
            photo.state = _PhotoState.failed;
            photo.error = error.message;
            _failed++;
          });
        }
        if (!mounted) return;
        setState(() => _processed++);
      }

      if (_added + _reused > 0) {
        await widget.api.sendUnapprovedPhotosForApproval(circleId);
      }
      if (widget.role.canReview && _added + _reused > 0) {
        _openableAlbum = await _buildAlbum(circleId);
      }
      if (mounted) setState(() => _finished = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Rebuilds the target album when one was given; otherwise creates the
  /// named album, or refreshes existing albums when no new title was given.
  Future<Album?> _buildAlbum(int circleId) async {
    final target = widget.targetAlbum;
    if (target != null) {
      await widget.api.generateAlbumPages(circleId, target.id);
      return widget.api.getAlbum(circleId, target.id);
    }
    final title = _albumTitleController.text.trim();
    final albums = await widget.api.listAlbums(circleId);
    if (title.isNotEmpty || albums.isEmpty) {
      final album = await widget.api.createAlbum(
        circleId,
        // A neutral default: a circle may be friends, a team, or a class,
        // not only a family.
        title: title.isEmpty ? 'Our Memory Book' : title,
      );
      await widget.api.generateAlbumPages(circleId, album.id);
      return album;
    }
    for (final album in albums) {
      await widget.api.generateAlbumPages(circleId, album.id);
    }
    return albums.first;
  }

  void _openAlbum(Album album) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlipAlbumScreen(
        api: widget.api,
        circleId: widget.circle.id,
        album: album,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.targetAlbum == null
                            ? 'Bring a whole album into the circle'
                            : 'Add photos to "${widget.targetAlbum!.title}"',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: Insets.sm),
                      Text(
                        widget.targetAlbum == null
                            ? 'Choose all the photos from an album on your phone. '
                                'Photos that are already in this circle are recognised '
                                'automatically, so nothing is stored twice. Captions '
                                'and stories can be added later, whenever anyone has '
                                'time.'
                            : 'Choose photos to add to this album. Photos already '
                                'in the circle are recognised automatically, so '
                                'nothing is stored twice. Captions and stories can '
                                'be added later.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.softInk),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Insets.md),
                PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _running ? null : _pickPhotos,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(_photos.isEmpty
                                ? 'Choose photos'
                                : 'Choose different photos'),
                          ),
                          const SizedBox(width: Insets.md),
                          if (_photos.isNotEmpty)
                            Text(
                              '${_photos.length} selected',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.softInk),
                            ),
                        ],
                      ),
                      if (_photos.isNotEmpty) ...[
                        const SizedBox(height: Insets.md),
                        Wrap(
                          spacing: Insets.sm,
                          runSpacing: Insets.sm,
                          children: [
                            for (final photo in _photos)
                              _PhotoTile(photo: photo),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.role.canReview && widget.targetAlbum == null) ...[
                  const SizedBox(height: Insets.md),
                  PaperCard(
                    child: TextField(
                      controller: _albumTitleController,
                      enabled: !_running,
                      decoration: appInput(
                        'New album title (optional)',
                        helper:
                            'Leave empty to refresh your existing albums instead of creating a new one.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Insets.md),
                if (_running) ...[
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(
                          value: _photos.isEmpty
                              ? null
                              : _processed / _photos.length,
                        ),
                        const SizedBox(height: Insets.sm),
                        Text(
                          'Adding photo ${(_processed + 1).clamp(1, _photos.length)} of ${_photos.length}…',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.softInk),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.rust),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Insets.md),
                ],
                if (_finished) ...[
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('All done', style: theme.textTheme.titleLarge),
                        const SizedBox(height: Insets.sm),
                        if (_added > 0)
                          _summaryRow(
                              theme,
                              Icons.check_circle_outline,
                              AppColors.success,
                              '$_added new ${_added == 1 ? 'photo' : 'photos'} added'),
                        if (_reused > 0)
                          _summaryRow(theme, Icons.link, AppColors.gold,
                              '$_reused already here — linked, not copied'),
                        if (_failed > 0)
                          _summaryRow(theme, Icons.error_outline,
                              AppColors.rust, '$_failed could not be added'),
                        const SizedBox(height: Insets.sm),
                        Text(
                          widget.role.canReview
                              ? 'They were sent for family approval. Once everyone approves, you can update the album pages.'
                              : 'They were sent for family approval. Everyone in the circle will be asked to approve them.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.softInk),
                        ),
                        if (_openableAlbum != null) ...[
                          const SizedBox(height: Insets.md),
                          FilledButton.icon(
                            onPressed: () => _openAlbum(_openableAlbum!),
                            icon: const Icon(Icons.auto_stories_outlined),
                            label: const Text('Open the album'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                ],
                FilledButton.icon(
                  onPressed: _photos.isEmpty || _running ? null : _run,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(_photos.isEmpty
                      ? 'Choose photos first'
                      : 'Add ${_photos.length} ${_photos.length == 1 ? 'photo' : 'photos'} to the circle'),
                ),
                const SizedBox(height: Insets.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(ThemeData theme, IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Insets.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final _BulkPhoto photo;

  @override
  Widget build(BuildContext context) {
    final bytes = photo.file.bytes;
    final (icon, color) = switch (photo.state) {
      _PhotoState.waiting => (null, null),
      _PhotoState.working => (Icons.more_horiz, AppColors.softInk),
      _PhotoState.added => (Icons.check_circle, AppColors.success),
      _PhotoState.alreadyHere => (Icons.link, AppColors.gold),
      _PhotoState.failed => (Icons.error, AppColors.rust),
    };
    return Tooltip(
      message: photo.error ?? photo.file.name,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: bytes == null
                  ? const ColoredBox(
                      color: Color(0xFFEFE7D7),
                      child:
                          Icon(Icons.photo_outlined, color: AppColors.softInk),
                    )
                  : Image.memory(bytes,
                      fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          if (icon != null)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ),
        ],
      ),
    );
  }
}
