import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../i18n/index.dart';
import '../widgets/paper_card.dart';

/// Circle settings: owners can rename the circle and update its
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
                if (widget.role.isOwner)
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
                      Text(context.t('settings.moreToCome'),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: Insets.xs),
                      Text(
                        context.t('settings.moreText'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.softInk),
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
