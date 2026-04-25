import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../core/widgets/gradient_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                const Center(child: AppLogo(size: 104)),
                const SizedBox(height: 32),
                Text(
                  'DiaryAI',
                  style: theme.textTheme.displaySmall?.copyWith(fontSize: 44),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Text(
                  'Зашифрованный дневник.\nРаботает в первую очередь у вас на устройстве.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 3),
                GradientButton(
                  onPressed: () => context.push('/create-profile'),
                  child: const Text('Создать новый дневник'),
                ),
                const SizedBox(height: 12),
                GlassButton(
                  onPressed: () => context.push('/restore'),
                  child: const Text('У меня уже есть аккаунт'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    onPressed: () => context.push('/settings/server'),
                    label: const Text('Адрес сервера'),
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

