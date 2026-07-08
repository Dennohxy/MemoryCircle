import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../i18n/index.dart';
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

  String _countKey(int number, String singularKey, String pluralKey) =>
      number == 1
          ? context.t(singularKey)
          : context.t(pluralKey, values: {'count': number});

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
                    Text(context.t('dashboard.whatNext'),
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: Insets.sm + Insets.xs),
                    _actions(glance),
                    const SizedBox(height: Insets.lg),
                    Text(context.t('dashboard.atGlance'),
                        style: theme.textTheme.titleLarge),
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
                    context.t('dashboard.roleLine', values: {
                      'role': widget.role.localizedLabel(context).toLowerCase(),
                    }),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.deepGreen),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.t('common.refresh'),
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
        _ActionSpec(
          icon: Icons.add_photo_alternate_outlined,
          title: context.t('nav.addMemory'),
          subtitle: context.t('dashboard.addMemorySubtitle'),
          section: CircleSection.addMemory,
          emphasized: true,
        ),
      if (widget.role.canContribute)
        _ActionSpec(
          icon: Icons.photo_library_outlined,
          title: context.t('nav.bulkAdd'),
          subtitle: context.t('dashboard.bulkAddSubtitle'),
          section: CircleSection.bulkAdd,
        ),
      _ActionSpec(
        icon: Icons.collections_outlined,
        title: context.t('nav.photos'),
        subtitle: context.t('dashboard.photosSubtitle'),
        section: CircleSection.photos,
      ),
      _ActionSpec(
        icon: Icons.fact_check_outlined,
        title: context.t('dashboard.approvePhotos'),
        subtitle: switch (glance?.pending) {
          null => context.t('dashboard.pendingUnknown'),
          0 => context.t('dashboard.pendingNone'),
          1 => context.t('dashboard.pendingOne'),
          final n => context.t('dashboard.pendingMany', values: {'count': n}),
        },
        section: CircleSection.photos,
      ),
      _ActionSpec(
        icon: Icons.auto_stories_outlined,
        title: context.t('albums.openAlbums'),
        subtitle: context.t('albums.flipThrough'),
        section: CircleSection.albums,
      ),
      _ActionSpec(
        icon: Icons.group_outlined,
        title: context.t('nav.members'),
        subtitle: context.t('dashboard.membersSubtitle'),
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
      return PaperCard(
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Insets.md),
            Text(context.t('dashboard.checking')),
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
                ? context.t('dashboard.countAlbumFailed')
                : _countKey(glance.approved!, 'dashboard.memoryInAlbumOne',
                    'dashboard.memoryInAlbumMany'),
          ),
          row(
            Icons.hourglass_empty,
            switch (glance.pending) {
              null => context.t('dashboard.countPendingFailed'),
              0 => context.t('dashboard.nothingForReview'),
              final int n => _countKey(n, 'dashboard.memoryWaitingOne',
                  'dashboard.memoryWaitingMany'),
            },
          ),
          row(
            Icons.menu_book_outlined,
            switch (glance.albums) {
              null => context.t('dashboard.countAlbumsFailed'),
              0 => context.t('dashboard.noAlbums'),
              final int n =>
                _countKey(n, 'dashboard.albumOne', 'dashboard.albumMany'),
            },
          ),
          row(
            health == null
                ? Icons.favorite_border
                : (health.healthy
                    ? Icons.check_circle_outline
                    : Icons.error_outline),
            health == null
                ? context.t('dashboard.healthFailed')
                : (health.healthy
                    ? context.t('dashboard.healthReady')
                    : _countKey(
                        health.missingCount,
                        'dashboard.photoAttentionOne',
                        'dashboard.photoAttentionMany')),
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
