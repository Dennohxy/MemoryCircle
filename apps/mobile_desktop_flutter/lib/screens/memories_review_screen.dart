import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/authed_image.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/memory_card.dart';

/// Memories waiting for a decision, plus the photos already in the album so
/// their captions and stories can be edited anytime.
class MemoriesReviewView extends StatefulWidget {
  const MemoriesReviewView({
    super.key,
    required this.api,
    required this.circle,
  });

  final ApiClient api;
  final Circle circle;

  @override
  State<MemoriesReviewView> createState() => _MemoriesReviewViewState();
}

class _ReviewData {
  const _ReviewData(this.memories, this.namesByUserId);

  final List<Memory> memories;
  final Map<int, String> namesByUserId;
}

class _MemoriesReviewViewState extends State<MemoriesReviewView> {
  String _status = 'pending';
  late Future<_ReviewData> _future = _load();

  Future<_ReviewData> _load() async {
    final results = await Future.wait([
      widget.api.listMemories(widget.circle.id, status: _status),
      widget.api.listMembers(widget.circle.id),
    ]);
    final members = results[1] as List<Member>;
    return _ReviewData(
      results[0] as List<Memory>,
      {for (final member in members) member.userId: member.displayName},
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _openMemory(Memory memory, String sentBy) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReviewMemoryScreen(
        api: widget.api,
        circle: widget.circle,
        memory: memory,
        sentBy: sentBy,
        editOnly: _status == 'approved',
      ),
    ));
    if (changed == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Insets.md),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Waiting')),
              ButtonSegment(value: 'approved', label: Text('In the album')),
            ],
            selected: {_status},
            onSelectionChanged: (selection) {
              setState(() {
                _status = selection.first;
                _future = _load();
              });
            },
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          child: FutureBuilder<_ReviewData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorState(
                    message: '${snapshot.error}', onRetry: _refresh);
              }
              if (!snapshot.hasData) {
                return const LoadingState(message: 'Gathering memories…');
              }
              final data = snapshot.data!;
              if (data.memories.isEmpty) {
                return _status == 'pending'
                    ? EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'Nothing to review',
                        message:
                            'When someone sends a new memory, it will appear here for you to look at.',
                        actionLabel: 'Check again',
                        onAction: _refresh,
                      )
                    : EmptyState(
                        icon: Icons.auto_stories_outlined,
                        title: 'The album is empty',
                        message:
                            'Once memories are added to the album, you can polish their captions and stories here.',
                        actionLabel: 'Check again',
                        onAction: _refresh,
                      );
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(Insets.md),
                    children: [
                      Text(
                        _status == 'pending'
                            ? 'These memories are waiting for a decision. Tap one to take a closer look.'
                            : 'These photos are in the album. Tap one to edit its caption or story.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.softInk),
                      ),
                      const SizedBox(height: Insets.md),
                      for (final memory in data.memories) ...[
                        MemoryCard(
                          api: widget.api,
                          memory: memory,
                          sentBy: memory.submittedBy == null
                              ? null
                              : data.namesByUserId[memory.submittedBy],
                          onTap: () => _openMemory(
                            memory,
                            memory.submittedBy == null
                                ? ''
                                : data.namesByUserId[memory.submittedBy] ?? '',
                          ),
                        ),
                        const SizedBox(height: Insets.sm + Insets.xs),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Full view of a single memory: read the story, tidy the words, then either
/// decide what happens to it (review) or simply save the edits (editOnly).
class ReviewMemoryScreen extends StatefulWidget {
  const ReviewMemoryScreen({
    super.key,
    required this.api,
    required this.circle,
    required this.memory,
    required this.sentBy,
    this.editOnly = false,
  });

  final ApiClient api;
  final Circle circle;
  final Memory memory;
  final String sentBy;

  /// True when the memory is already in the album and only its words are
  /// being polished.
  final bool editOnly;

  @override
  State<ReviewMemoryScreen> createState() => _ReviewMemoryScreenState();
}

class _ReviewMemoryScreenState extends State<ReviewMemoryScreen> {
  late final _captionController =
      TextEditingController(text: widget.memory.caption);
  late final _storyController =
      TextEditingController(text: widget.memory.story);
  late final _eventController =
      TextEditingController(text: widget.memory.eventName);
  late final _locationController =
      TextEditingController(text: widget.memory.locationText);
  late final _dateController =
      TextEditingController(text: formatFriendlyDate(widget.memory.memoryDate));

  late DateTime? _memoryDate = widget.memory.memoryDate;

  String? _busyAction;
  String? _error;

  @override
  void dispose() {
    _captionController.dispose();
    _storyController.dispose();
    _eventController.dispose();
    _locationController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _edits() {
    final edits = <String, dynamic>{};
    if (_captionController.text.trim() != widget.memory.caption) {
      edits['caption'] = _captionController.text.trim();
    }
    if (_storyController.text.trim() != widget.memory.story) {
      edits['story'] = _storyController.text.trim();
    }
    if (_eventController.text.trim() != widget.memory.eventName) {
      edits['event_name'] = _eventController.text.trim();
    }
    if (_locationController.text.trim() != widget.memory.locationText) {
      edits['location_text'] = _locationController.text.trim();
    }
    if (_memoryDate != null && _memoryDate != widget.memory.memoryDate) {
      edits['memory_date'] = _memoryDate!.toIso8601String();
    }
    return edits;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _memoryDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _memoryDate = picked;
        _dateController.text = formatFriendlyDate(picked);
      });
    }
  }

  Future<void> _saveEdits() async {
    final edits = _edits();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (edits.isEmpty) {
      navigator.pop(false);
      return;
    }
    setState(() {
      _busyAction = 'save';
      _error = null;
    });
    try {
      await widget.api.updateMemory(widget.circle.id, widget.memory.id, edits);
      messenger.showSnackBar(
          const SnackBar(content: Text('Your changes were saved.')));
      navigator.pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busyAction = null;
        });
      }
    }
  }

  Future<void> _decide(String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busyAction = action;
      _error = null;
    });
    try {
      final circleId = widget.circle.id;
      final memoryId = widget.memory.id;
      String message;
      switch (action) {
        case 'approve':
          final updated = await widget.api
              .approveMemory(circleId, memoryId, edits: _edits());
          message = updated.approvalStatus == 'approved'
              ? 'Everyone has approved this photo. It can enter the album.'
              : 'Your approval was recorded. Waiting for the rest of the family.';
        case 'changes':
          await widget.api.requestChanges(circleId, memoryId);
          message = 'We let them know some changes are needed.';
        default:
          await widget.api.rejectMemory(circleId, memoryId);
          message = 'This memory will not be included in the album.';
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
      navigator.pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busyAction = null;
        });
      }
    }
  }

  Future<void> _confirmReject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this memory out?'),
        content: const Text(
            'It will not appear in the album. The person who sent it will still be able to see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep deciding'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.rust),
            child: const Text('Do not include'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _decide('reject');
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyAction != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.editOnly ? 'Edit Memory' : 'Review Memory')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.rust),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (widget.editOnly)
                FilledButton.icon(
                  onPressed: busy ? null : _saveEdits,
                  icon: _busyAction == 'save'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Save changes'),
                )
              else
                Wrap(
                  spacing: Insets.sm + Insets.xs,
                  runSpacing: Insets.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : () => _decide('approve'),
                      icon: _busyAction == 'approve'
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Add to album'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _decide('changes'),
                      icon: _busyAction == 'changes'
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_note),
                      label: const Text('Ask for changes'),
                    ),
                    TextButton(
                      onPressed: busy ? null : _confirmReject,
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.rust),
                      child: const Text('Do not include'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(Insets.md),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _photo(),
                  ),
                ),
                const SizedBox(height: Insets.md),
                ..._formFields(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  color: const Color(0xFFEFE8D8),
                  padding: const EdgeInsets.all(Insets.lg),
                  child: _photo(fit: BoxFit.contain),
                ),
              ),
              Expanded(
                flex: 4,
                child: ListView(
                  padding: const EdgeInsets.all(Insets.lg),
                  children: _formFields(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _photo({BoxFit fit = BoxFit.cover}) {
    final asset = widget.memory.asset;
    if (asset == null) {
      return const ColoredBox(
        color: Color(0xFFEFE7D7),
        child: Center(
          child: Icon(Icons.photo_outlined, color: AppColors.softInk),
        ),
      );
    }
    return AuthedImage(api: widget.api, path: asset.displayUrl, fit: fit);
  }

  List<Widget> _formFields() {
    final theme = Theme.of(context);
    return [
      if (widget.sentBy.isNotEmpty) ...[
        Text(
          'Sent by ${widget.sentBy}',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
        ),
        const SizedBox(height: Insets.md),
      ],
      Text(
        widget.editOnly
            ? 'Update the caption and story whenever you like — the album shows the latest words.'
            : 'You can tidy the words before adding this to the album.',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
      ),
      const SizedBox(height: Insets.md),
      TextField(
        controller: _captionController,
        decoration: appInput('Short caption'),
      ),
      const SizedBox(height: Insets.md),
      TextField(
        controller: _storyController,
        minLines: 4,
        maxLines: 8,
        decoration: appInput('What is the story behind this photo?'),
      ),
      const SizedBox(height: Insets.md),
      TextField(
        controller: _eventController,
        decoration: appInput('What was the occasion?'),
      ),
      const SizedBox(height: Insets.md),
      TextField(
        controller: _dateController,
        readOnly: true,
        onTap: _pickDate,
        decoration: appInput(
          'When did this happen?',
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
      ),
      const SizedBox(height: Insets.md),
      TextField(
        controller: _locationController,
        decoration: appInput('Where was this?'),
      ),
    ];
  }
}
