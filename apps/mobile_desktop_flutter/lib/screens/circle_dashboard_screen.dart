import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/paper_card.dart';

/// The circle overview: what would you like to do, plus an at-a-glance
/// summary in plain language.
class CircleDashboardView extends StatefulWidget {
  const CircleDashboardView({
    super.key,
    required this.api,
    required this.circle,
    required this.role,
    required this.onOpen,
  });

  final ApiClient api;
  final Circle circle;
  final CircleRole role;
  final void Function(CircleSection section) onOpen;

  @override
  State<CircleDashboardView> createState() => _CircleDashboardViewState();
}

class _Glance {
  int? approved;
  int? pending;
  int? albums;
  CircleHealth? health;
}

class _CircleDashboardViewState extends State<CircleDashboardView> {
  late Future<_Glance> _glance = _load();

  Future<_Glance> _load() async {
    final glance = _Glance();
    Future<void> quiet(Future<void> Function() run) async {
      try {
        await run();
      } catch (_) {
        // Each panel degrades gracefully on its own.
      }
    }

    await Future.wait([
      quiet(() async => glance.approved =
          (await widget.api.listMemories(widget.circle.id, status: 'approved'))
              .length),
      quiet(() async => glance.pending =
          (await widget.api.listMemories(widget.circle.id, status: 'pending'))
              .length),
      quiet(() async => glance.albums =
          (await widget.api.listAlbums(widget.circle.id)).length),
      quiet(() async =>
          glance.health = await widget.api.circleHealth(widget.circle.id)),
    ]);
    return glance;
  }

  void _refresh() => setState(() => _glance = _load());

  String _count(int number, String singular, String plural) =>
      number == 1 ? '1 $singular' : '$number $plural';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<_Glance>(
      future: _glance,
      builder: (context, snapshot) {
        final glance = snapshot.data;
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(theme),
                    const SizedBox(height: Insets.lg),
                    Text('What would you like to do?',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: Insets.sm + Insets.xs),
                    _actions(glance),
                    const SizedBox(height: Insets.lg),
                    Text('At a glance', style: theme.textTheme.titleLarge),
                    const SizedBox(height: Insets.sm + Insets.xs),
                    _glancePanel(theme, glance),
                    const SizedBox(height: Insets.lg),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(ThemeData theme) {
    return PaperCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.circle.name, style: theme.textTheme.headlineSmall),
                if (widget.circle.description.isNotEmpty) ...[
                  const SizedBox(height: Insets.xs),
                  Text(
                    widget.circle.description,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.softInk),
                  ),
                ],
                const SizedBox(height: Insets.sm + Insets.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Insets.sm + Insets.xs, vertical: Insets.xs),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Text(
                    'You are the ${widget.role.label.toLowerCase()} of this circle',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.deepGreen),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: AppColors.softInk),
          ),
        ],
      ),
    );
  }

  Widget _actions(_Glance? glance) {
    final actions = <_ActionSpec>[
      if (widget.role.canContribute)
        const _ActionSpec(
          icon: Icons.add_photo_alternate_outlined,
          title: 'Add a Memory',
          subtitle: 'Share a photo and the story behind it',
          section: CircleSection.addMemory,
          emphasized: true,
        ),
      if (widget.role.canReview)
        _ActionSpec(
          icon: Icons.fact_check_outlined,
          title: 'Review Memories',
          subtitle: switch (glance?.pending) {
            null => 'See what family has sent in',
            0 => 'Nothing waiting right now',
            1 => '1 memory waiting for review',
            final n => '$n memories waiting for review',
          },
          section: CircleSection.review,
        ),
      const _ActionSpec(
        icon: Icons.auto_stories_outlined,
        title: 'Open My Albums',
        subtitle: 'Flip through the family album',
        section: CircleSection.albums,
      ),
      const _ActionSpec(
        icon: Icons.group_outlined,
        title: 'Family Members',
        subtitle: 'See who is in this circle',
        section: CircleSection.members,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * Insets.md) / columns;
        return Wrap(
          spacing: Insets.md,
          runSpacing: Insets.md,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: _ActionCard(
                  spec: action,
                  onTap: () => widget.onOpen(action.section),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _glancePanel(ThemeData theme, _Glance? glance) {
    if (glance == null) {
      return const PaperCard(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: Insets.md),
            Text('Checking on your circle…'),
          ],
        ),
      );
    }

    Widget row(IconData icon, String text,
        {Color color = AppColors.deepGreen, VoidCallback? onTap}) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Insets.sm + Insets.xs),
            Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            if (onTap != null)
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.softInk),
          ],
        ),
      );
      return onTap == null ? content : InkWell(onTap: onTap, child: content);
    }

    final health = glance.health;
    return PaperCard(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.sm),
      child: Column(
        children: [
          row(
            Icons.photo_library_outlined,
            glance.approved == null
                ? 'We could not count the album memories right now.'
                : _count(glance.approved!, 'memory in the album',
                    'memories in the album'),
          ),
          row(
            Icons.hourglass_empty,
            switch (glance.pending) {
              null => 'We could not check for waiting memories right now.',
              0 => 'Nothing waiting for review',
              final int n => _count(n, 'memory waiting for review',
                  'memories waiting for review'),
            },
          ),
          row(
            Icons.menu_book_outlined,
            switch (glance.albums) {
              null => 'We could not count the albums right now.',
              0 => 'No albums yet',
              final int n => _count(n, 'album created', 'albums created'),
            },
          ),
          row(
            health == null
                ? Icons.favorite_border
                : (health.healthy
                    ? Icons.check_circle_outline
                    : Icons.error_outline),
            health == null
                ? 'We could not check photo health right now.'
                : (health.healthy
                    ? 'All display photos are ready'
                    : _count(health.missingCount, 'photo needs attention',
                        'photos need attention')),
            color: health == null
                ? AppColors.softInk
                : (health.healthy ? AppColors.success : AppColors.attention),
            onTap: () => widget.onOpen(CircleSection.health),
          ),
        ],
      ),
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.section,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CircleSection section;
  final bool emphasized;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.spec, required this.onTap});

  final _ActionSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = spec.emphasized ? Colors.white : AppColors.ink;
    return PaperCard(
      onTap: onTap,
      color: spec.emphasized ? AppColors.deepGreen : AppColors.paper,
      borderColor: spec.emphasized ? AppColors.forest : AppColors.outline,
      padding: const EdgeInsets.all(Insets.md + Insets.xs),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: spec.emphasized
                  ? Colors.white.withValues(alpha: 0.14)
                  : AppColors.parchment,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              spec.icon,
              color: spec.emphasized ? Colors.white : AppColors.deepGreen,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: theme.textTheme.titleMedium?.copyWith(color: onColor),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: spec.emphasized
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.softInk,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: spec.emphasized
                  ? Colors.white.withValues(alpha: 0.8)
                  : AppColors.softInk),
        ],
      ),
    );
  }
}
