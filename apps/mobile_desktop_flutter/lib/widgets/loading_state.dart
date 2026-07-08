import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../i18n/index.dart';

/// Centered spinner with a gentle message.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: Insets.md),
          Text(
            message ?? context.t('common.loading'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.softInk),
          ),
        ],
      ),
    );
  }
}
