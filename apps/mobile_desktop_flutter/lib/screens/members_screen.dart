import 'package:flutter/material.dart';

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
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
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
                      FilledButton.tonalIcon(
                        onPressed: _invite,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Invite someone'),
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
