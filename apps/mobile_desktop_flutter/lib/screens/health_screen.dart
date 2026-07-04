import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/paper_card.dart';

/// Album health translated into plain language, with future safeguards
/// clearly framed as coming later.
class HealthView extends StatefulWidget {
  const HealthView({super.key, required this.api, required this.circle});

  final ApiClient api;
  final Circle circle;

  @override
  State<HealthView> createState() => _HealthViewState();
}

class _HealthViewState extends State<HealthView> {
  late Future<CircleHealth> _health = widget.api.circleHealth(widget.circle.id);

  void _refresh() =>
      setState(() => _health = widget.api.circleHealth(widget.circle.id));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<CircleHealth>(
      future: _health,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(message: '${snapshot.error}', onRetry: _refresh);
        }
        if (!snapshot.hasData) {
          return const LoadingState(message: 'Checking your photos…');
        }
        final health = snapshot.data!;
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PaperCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: (health.healthy
                                      ? AppColors.success
                                      : AppColors.attention)
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              health.healthy
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: health.healthy
                                  ? AppColors.success
                                  : AppColors.attention,
                            ),
                          ),
                          const SizedBox(width: Insets.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  health.healthy
                                      ? 'All display photos are ready'
                                      : 'Some album photos need attention',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: Insets.xs),
                                Text(
                                  health.healthy
                                      ? 'We checked ${health.assetCount} ${health.assetCount == 1 ? 'photo' : 'photos'} and everything is in place.'
                                      : '${health.missingCount} of ${health.assetCount} photos could not be found. Try uploading those photos again, or ask the person who added them to send them once more.',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: AppColors.softInk),
                                ),
                                const SizedBox(height: Insets.sm),
                                TextButton.icon(
                                  onPressed: _refresh,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Check again'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    PaperCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Coming later',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: Insets.sm),
                          for (final item in const [
                            'Backing up this circle to a family archive drive',
                            'Recovering photos from family devices',
                            'Checking connected photo sources',
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: Insets.xs),
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule,
                                      size: 18, color: AppColors.softInk),
                                  const SizedBox(width: Insets.sm + Insets.xs),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: AppColors.softInk),
                                    ),
                                  ),
                                ],
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
      },
    );
  }
}
