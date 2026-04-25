import 'package:flutter/material.dart';

import '../theme.dart';

/// Уникальная кнопка DiaryAI с градиентной заливкой и мягкой тенью.
/// Принимает [onPressed], [child] и опциональный [gradient] — по умолчанию primary.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final double height;
  final bool fullWidth;
  final bool loading;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.gradient,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    this.height = 54,
    this.fullWidth = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final g = gradient ?? AppGradients.primary;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: height,
            width: fullWidth ? double.infinity : null,
            decoration: BoxDecoration(
              gradient: g,
              borderRadius: BorderRadius.circular(16),
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: (g.colors.first).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Padding(
              padding: padding,
              child: Center(
                child: loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : DefaultTextStyle.merge(
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                        child: IconTheme(
                          data: const IconThemeData(color: Colors.white, size: 20),
                          child: child,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Полупрозрачная вторичная кнопка — стеклянный эффект на градиентном фоне.
class GlassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double height;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.55),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.25),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              child: IconTheme(
                data: IconThemeData(color: theme.colorScheme.onSurface, size: 20),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
