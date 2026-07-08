import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/authed_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';

class PhotosView extends StatefulWidget {
  const PhotosView({
    super.key,
    required this.api,
    required this.circle,
    required this.role,
  });

  final ApiClient api;
  final Circle circle;
  final CircleRole role;

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  late Future<List<UploadedPhoto>> _photos =
      widget.api.listUploadedPhotos(widget.circle.id);
  bool _busy = false;
  bool _sendingAll = false;

  void _refresh() =>
      setState(() => _photos = widget.api.listUploadedPhotos(widget.circle.id));

  Future<void> _approve(Memory memory) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated =
          await widget.api.approveMemory(widget.circle.id, memory.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(updated.approvalStatus == 'approved'
            ? 'All reviewers have approved this photo. It can enter the album.'
            : 'Your approval was recorded.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendAllForApproval() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sendingAll = true);
    try {
      final result =
          await widget.api.sendUnapprovedPhotosForApproval(widget.circle.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(
          '${result.sent} sent for approval. ${result.notificationsQueued} member notifications queued.',
        ),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sendingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UploadedPhoto>>(
      future: _photos,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(message: '${snapshot.error}', onRetry: _refresh);
        }
        if (!snapshot.hasData) {
          return const LoadingState(message: 'Gathering uploaded photos...');
        }
        final photos = snapshot.data!;
        if (photos.isEmpty) {
          return EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No uploaded photos yet',
            message:
                'Photos will appear here as soon as family members upload them, before they are arranged into albums.',
            actionLabel: 'Check again',
            onAction: _refresh,
          );
        }
        return Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.md, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _sendingAll ? null : _sendAllForApproval,
                  icon: _sendingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                  label: const Text('Send unapproved photos for approval'),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100
                      ? 4
                      : constraints.maxWidth >= 760
                          ? 3
                          : 2;
                  return GridView.builder(
                    padding: const EdgeInsets.all(Insets.md),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: Insets.md,
                      mainAxisSpacing: Insets.md,
                      childAspectRatio: columns == 2 ? 0.72 : 0.78,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (context, index) => _PhotoTile(
                      api: widget.api,
                      photo: photos[index],
                      currentUserId: widget.api.currentUser?.id,
                      canReview: widget.role.canReview,
                      busy: _busy,
                      onApprove: _approve,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.api,
    required this.photo,
    required this.currentUserId,
    required this.canReview,
    required this.busy,
    required this.onApprove,
  });

  final ApiClient api;
  final UploadedPhoto photo;
  final int? currentUserId;
  final bool canReview;
  final bool busy;
  final ValueChanged<Memory> onApprove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memory = photo.memory;
    final status = memory?.approvalStatus ?? 'uploaded';
    final canApprove = canReview &&
        memory != null &&
        status == 'pending' &&
        !memory.approval.hasVoted(currentUserId);
    return Material(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFEFE8D8),
              child: AuthedImage(
                api: api,
                path: photo.asset.displayUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory?.caption.isNotEmpty == true
                      ? memory!.caption
                      : photo.asset.originalFilename,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  _statusLine(memory, status),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.softInk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (canApprove) ...[
                  const SizedBox(height: Insets.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => onApprove(memory),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve photo'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLine(Memory? memory, String status) {
    if (memory == null) return 'Uploaded, not sent for album review yet';
    if (status == 'approved') return 'Approved for album';
    if (status == 'pending') {
      return 'Waiting for reviewer approval: ${memory.approval.approvalsHave} of ${memory.approval.approvalsNeeded}';
    }
    if (status == 'changes_requested') return 'Changes requested';
    if (status == 'rejected') return 'Not included';
    return 'Uploaded';
  }
}
