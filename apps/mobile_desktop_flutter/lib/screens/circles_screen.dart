import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/circle_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';

/// The list of memory circles the signed-in person belongs to.
class CirclesScreen extends StatefulWidget {
  const CirclesScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onSignOut,
  });

  final ApiClient api;
  final UserProfile user;
  final VoidCallback onSignOut;

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> {
  bool _autoOpened = false;
  late Future<List<Circle>> _circles = _load();

  Future<List<Circle>> _load() async {
    final circles = await widget.api.listCircles();
    // With exactly one circle there is nothing to choose, so open it right
    // away. Backing out still shows the list.
    if (!_autoOpened && circles.length == 1 && mounted) {
      _autoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openCircle(circles.first);
      });
    }
    return circles;
  }

  void _refresh() => setState(() => _circles = _load());

  /// Opens the search dialog to find a circle by name and ask to join.
  Future<void> _findCircle() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FindCircleDialog(api: widget.api),
    );
    if (mounted) _refresh();
  }

  Future<void> _openCircle(Circle circle) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CircleShell(api: widget.api, circle: circle),
    ));
    if (mounted) _refresh();
  }

  Future<void> _createCircle() async {
    final input = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => const _CreateCircleDialog(),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final circle = await widget.api.createCircle(
        name: input.name,
        description: input.description,
      );
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Your circle is ready.')),
      );
      await _openCircle(circle);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Memory Circles'),
        actions: [
          IconButton(
            tooltip: 'Find a circle',
            icon: const Icon(Icons.travel_explore),
            onPressed: _findCircle,
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (value) {
              if (value == 'signout') widget.onSignOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.user.displayName,
                        style: theme.textTheme.titleSmall),
                    Text(widget.user.email, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: Insets.sm),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.parchment,
                child: Text(
                  widget.user.initials,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.deepGreen),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCircle,
        icon: const Icon(Icons.add),
        label: const Text('New circle'),
      ),
      body: FutureBuilder<List<Circle>>(
        future: _circles,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          }
          if (!snapshot.hasData) {
            return const LoadingState(message: 'Opening your circles…');
          }
          final circles = snapshot.data!;
          if (circles.isEmpty) {
            return EmptyState(
              icon: Icons.group_add_outlined,
              title: 'Start your first memory circle',
              message:
                  'A memory circle is a private space where your family gathers photos and stories into a shared album.',
              actionLabel: 'Create a circle',
              onAction: _createCircle,
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(Insets.md),
                children: [
                  Text(
                    'Choose a circle to open its albums and memories.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.softInk),
                  ),
                  const SizedBox(height: Insets.md),
                  for (final circle in circles) ...[
                    CircleCard(
                      circle: circle,
                      onOpen: () => _openCircle(circle),
                    ),
                    const SizedBox(height: Insets.sm + Insets.xs),
                  ],
                  const SizedBox(height: 72),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreateCircleDialog extends StatefulWidget {
  const _CreateCircleDialog();

  @override
  State<_CreateCircleDialog> createState() => _CreateCircleDialogState();
}

class _CreateCircleDialogState extends State<_CreateCircleDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCreate = _nameController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Create a memory circle'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Give your circle a name your family will recognize.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: appInput('Circle name',
                  hint: 'For example, "The Otieno Family"'),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 3,
              decoration: appInput('What is this circle about? (optional)'),
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
                    name: _nameController.text.trim(),
                    description: _descriptionController.text.trim(),
                  ))
              : null,
          child: const Text('Create circle'),
        ),
      ],
    );
  }
}

/// Search circles by name and ask to join one; the owner decides.
class _FindCircleDialog extends StatefulWidget {
  const _FindCircleDialog({required this.api});

  final ApiClient api;

  @override
  State<_FindCircleDialog> createState() => _FindCircleDialogState();
}

class _FindCircleDialogState extends State<_FindCircleDialog> {
  final _searchController = TextEditingController();
  Future<List<CircleSearchResult>>? _results;
  final Set<int> _requested = {};
  int? _requestingId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    setState(() {
      _results = query.length < 2 ? null : widget.api.searchCircles(query);
    });
  }

  Future<void> _request(CircleSearchResult circle) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _requestingId = circle.id);
    try {
      await widget.api.requestToJoin(circle.id);
      if (!mounted) return;
      setState(() => _requested.add(circle.id));
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Your request to join "${circle.name}" was sent. The circle owner will decide.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _requestingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Find a circle'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: appInput(
                'Search by circle name',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: Insets.md),
            SizedBox(
              height: 300,
              child: _results == null
                  ? Center(
                      child: Text(
                        'Type at least two letters to find a family circle to join.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.softInk),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : FutureBuilder<List<CircleSearchResult>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return ErrorState(message: '${snapshot.error}');
                        }
                        if (!snapshot.hasData) {
                          return const LoadingState(message: 'Searching…');
                        }
                        final circles = snapshot.data!;
                        if (circles.isEmpty) {
                          return Center(
                            child: Text(
                              'No circles matched that name.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.softInk),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: circles.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final circle = circles[index];
                            final requested = circle.isPending ||
                                _requested.contains(circle.id);
                            final Widget trailing;
                            if (circle.isMember) {
                              trailing = Text('Joined',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.softInk));
                            } else if (requested) {
                              trailing = Text('Requested',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.softInk));
                            } else if (_requestingId == circle.id) {
                              trailing = const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              );
                            } else {
                              trailing = FilledButton(
                                onPressed: () => _request(circle),
                                child: const Text('Request'),
                              );
                            }
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(circle.name),
                              subtitle: circle.description.isEmpty
                                  ? null
                                  : Text(circle.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                              trailing: trailing,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
