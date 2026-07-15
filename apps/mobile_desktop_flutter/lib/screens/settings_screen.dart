import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../i18n/index.dart';
import '../widgets/paper_card.dart';

/// Circle settings: owners and editors can rename the circle and update its
/// description; everyone else sees a modest read-only view.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.api,
    required this.circle,
    required this.role,
    required this.onUpdated,
  });

  final ApiClient api;
  final Circle circle;
  final CircleRole role;
  final void Function(Circle circle) onUpdated;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final _nameController = TextEditingController(text: widget.circle.name);
  late final _descriptionController =
      TextEditingController(text: widget.circle.description);

  bool _saving = false;

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

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final updated = await widget.api.updateCircle(
        widget.circle.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
      );
      if (!mounted) return;
      widget.onUpdated(updated);
      messenger
          .showSnackBar(SnackBar(content: Text(context.t('settings.saved'))));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.role.canEdit)
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(context.t('settings.about'),
                            style: theme.textTheme.titleLarge),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _nameController,
                          decoration: appInput(context.t('circles.nameLabel')),
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 4,
                          decoration:
                              appInput(context.t('circles.descriptionLabel')),
                        ),
                        const SizedBox(height: Insets.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed:
                                _saving || _nameController.text.trim().isEmpty
                                    ? null
                                    : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(context.t('settings.saveChanges')),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.circle.name,
                            style: theme.textTheme.titleLarge),
                        if (widget.circle.description.isNotEmpty) ...[
                          const SizedBox(height: Insets.xs),
                          Text(
                            widget.circle.description,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.softInk),
                          ),
                        ],
                        const SizedBox(height: Insets.sm),
                        Text(
                          context.t('settings.ownerOnly'),
                          style: theme.textTheme.bodySmall
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
                      Text('Your account', style: theme.textTheme.titleMedium),
                      const SizedBox(height: Insets.xs),
                      Text(
                        'Change the password you use to sign in.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.softInk),
                      ),
                      const SizedBox(height: Insets.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _ChangePasswordDialog(api: widget.api),
                          ),
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text('Change password'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.api});

  final ApiClient api;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_newController.text.length < 8) {
      setState(() => _error = 'Choose at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Your password was changed.')));
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentController,
              obscureText: true,
              decoration: appInput('Current password'),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _newController,
              obscureText: true,
              decoration: appInput('New password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: Insets.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.attention)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
