import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Centered spinner with a gentle message.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = 'Just a moment…'});

  final String message;

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
            message,
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
