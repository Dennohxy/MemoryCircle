import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/paper_card.dart';

/// The people in a circle, with owner-only role controls and invitations.
class MembersView extends StatefulWidget {
  const MembersView({
    super.key,
    required this.api,
    required this.circle,
    required this.role,
  });

  final ApiClient api;
  final Circle circle;
  final CircleRole role;

  @override
  State<MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends State<MembersView> {
  late Future<List<Member>> _members = widget.api.listMembers(widget.circle.id);

  void _refresh() =>
      setState(() => _members = widget.api.listMembers(widget.circle.id));

  Future<void> _editRole(Member member) async {
    final chosen = await showDialog<CircleRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('What should ${member.displayName} be able to do?'),
        children: [
          for (final role in CircleRole.values)
            ListTile(
              leading: Icon(
                member.role == role
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: member.role == role
                    ? AppColors.deepGreen
                    : AppColors.softInk,
              ),
              title: Text(role.label),
              subtitle: Text(role.blurb),
              onTap: () => Navigator.of(context).pop(role),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == member.role || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.updateMemberRole(widget.circle.id, member.id, chosen);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${member.displayName} is now a ${chosen.label.toLowerCase()}.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _invite() async {
    final input =
        await showDialog<({String email, String name, CircleRole role})>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.inviteMember(
        widget.circle.id,
        email: input.email,
        displayName: input.name,
        role: input.role,
      );
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(
        content: Text('They have been added to the circle.'),
      ));
      await _shareInvite(input.email, input.name);
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Opens the search-by-name/email directory to add an already-registered
  /// person to the circle.
  Future<void> _addExisting() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FindPeopleDialog(
        api: widget.api,
        circleId: widget.circle.id,
      ),
    );
    if (mounted) _refresh();
  }

  String _inviteMessage(String email, String name) {
    final base = Uri.base;
    // On the web this is the address the app is being used from; elsewhere
    // fall back to the published app link.
    final appUrl = base.scheme.startsWith('http')
        ? '${base.scheme}://${base.authority}${base.path}'
        : 'https://dennohxy.github.io/MemoryCircle/';
    final inviter = widget.api.currentUser?.displayName ?? 'Your family';
    final greeting = name.isEmpty ? 'Hello!' : 'Hello $name!';
    return '$greeting\n\n'
        '$inviter invited you to "${widget.circle.name}" on Memory Circle — '
        'a private album for our family\'s photos and stories.\n\n'
        '1. Open: $appUrl\n'
        '2. Sign in with: $email\n'
        '3. New to Memory Circle? Your temporary password is ChangeMe123!\n\n'
        'See you in the album!';
  }

  /// Lets the owner send the invitation through WhatsApp, Messenger, SMS, or
  /// any other app on their phone via the system share sheet.
  Future<void> _shareInvite(String email, String name) async {
    final message = _inviteMessage(email, name);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share the invitation'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Text(
              message,
              style: Theme.of(dialogContext)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.softInk),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              messenger.showSnackBar(const SnackBar(
                content: Text('Invitation copied — paste it anywhere.'),
              ));
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share…'),
            onPressed: () async {
              try {
                await Share.share(message, subject: 'Join our Memory Circle');
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: message));
                messenger.showSnackBar(const SnackBar(
                  content: Text(
                      'Sharing is not available here, so the invitation was copied instead.'),
                ));
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Member>>(
      future: _members,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(message: '${snapshot.error}', onRetry: _refresh);
        }
        if (!snapshot.hasData) {
          return const LoadingState(message: 'Finding your family…');
        }
        final members = snapshot.data!;
        final myId = widget.api.currentUser?.id;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(Insets.md),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'The people who share this circle.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.softInk),
                      ),
                    ),
                    if (widget.role.isOwner)
                      Wrap(
                        spacing: Insets.sm,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _addExisting,
                            icon: const Icon(Icons.person_search),
                            label: const Text('Find people'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _invite,
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Invite'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                for (final member in members) ...[
                  PaperCard(
                    padding: const EdgeInsets.all(Insets.md),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.parchment,
                          child: Text(
                            initialsFor(member.displayName),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.deepGreen),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.userId == myId
                                    ? '${member.displayName} (you)'
                                    : member.displayName,
                                style: theme.textTheme.titleMedium,
                              ),
                              if (member.email.isNotEmpty)
                                Text(
                                  member.email,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.softInk),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Insets.sm + Insets.xs,
                                  vertical: Insets.xs),
                              decoration: BoxDecoration(
                                color: AppColors.parchment,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.outline),
                              ),
                              child: Text(
                                member.role.label,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppColors.deepGreen),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              member.role.blurb,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.softInk),
                            ),
                          ],
                        ),
                        if (widget.role.isOwner && member.userId != myId)
                          IconButton(
                            tooltip: 'Change role',
                            onPressed: () => _editRole(member),
                            icon: const Icon(Icons.edit_outlined,
                                size: 20, color: AppColors.softInk),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.sm + Insets.xs),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  CircleRole _role = CircleRole.contributor;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _emailController.text.trim();
    final canInvite = email.contains('@');
    return AlertDialog(
      title: const Text('Invite someone'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: appInput('Their email'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _nameController,
                decoration: appInput('Their name (optional)'),
              ),
              const SizedBox(height: Insets.md),
              Text('What should they be able to do?',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: Insets.xs),
              for (final role in CircleRole.values
                  .where((role) => role != CircleRole.owner)) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    _role == role
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color:
                        _role == role ? AppColors.deepGreen : AppColors.softInk,
                  ),
                  title: Text(role.label),
                  subtitle: Text(role.blurb),
                  onTap: () => setState(() => _role = role),
                ),
              ],
              const SizedBox(height: Insets.sm),
              Text(
                'If they are new to Memory Circle, they can sign in with this email and the temporary password ChangeMe123!.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.softInk),
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
          onPressed: canInvite
              ? () => Navigator.of(context).pop((
                    email: email,
                    name: _nameController.text.trim(),
                    role: _role,
                  ))
              : null,
          child: const Text('Add to circle'),
        ),
      ],
    );
  }
}

/// Owner-only directory: search already-registered people by name or email
/// and add them straight into the circle.
class _FindPeopleDialog extends StatefulWidget {
  const _FindPeopleDialog({required this.api, required this.circleId});

  final ApiClient api;
  final int circleId;

  @override
  State<_FindPeopleDialog> createState() => _FindPeopleDialogState();
}

class _FindPeopleDialogState extends State<_FindPeopleDialog> {
  final _searchController = TextEditingController();
  Future<List<DirectoryPerson>>? _results;
  final Set<int> _added = {};
  int? _addingId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    setState(() {
      _results = query.length < 2
          ? null
          : widget.api.searchPeople(widget.circleId, query);
    });
  }

  Future<void> _add(DirectoryPerson person) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _addingId = person.user.id);
    try {
      await widget.api.inviteMember(
        widget.circleId,
        email: person.user.email,
        displayName: person.user.displayName,
        role: CircleRole.contributor,
      );
      if (!mounted) return;
      setState(() => _added.add(person.user.id));
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${person.user.displayName} was added as a contributor. You can change their role anytime.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Find people to add'),
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
                'Search by name or email',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: Insets.md),
            SizedBox(
              height: 300,
              child: _results == null
                  ? Center(
                      child: Text(
                        'Type at least two letters to find people already on Memory Circle.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.softInk),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : FutureBuilder<List<DirectoryPerson>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return ErrorState(message: '${snapshot.error}');
                        }
                        if (!snapshot.hasData) {
                          return const LoadingState(message: 'Searching…');
                        }
                        final people = snapshot.data!;
                        if (people.isEmpty) {
                          return Center(
                            child: Text(
                              'No one matched. They may not have an account yet — use "Invite" to bring them in by email or link.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.softInk),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: people.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final person = people[index];
                            final added = person.alreadyMember ||
                                _added.contains(person.user.id);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.parchment,
                                child: Text(
                                  person.user.initials,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.deepGreen),
                                ),
                              ),
                              title: Text(person.user.displayName),
                              subtitle: Text(person.user.email),
                              trailing: added
                                  ? Text('In circle',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: AppColors.softInk))
                                  : _addingId == person.user.id
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : FilledButton(
                                          onPressed: () => _add(person),
                                          child: const Text('Add'),
                                        ),
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
