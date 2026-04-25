import 'package:flutter/material.dart';

import '../theme.dart';

/// Простой градиентный фон. Декоративные «облачка» убраны —
/// они вызывали проблемы с layout при определённых сочетаниях виджетов.
class GradientBackground extends StatelessWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? AppGradients.darkBackground : AppGradients.lightBackground,
      ),
      child: child,
    );
  }
}
