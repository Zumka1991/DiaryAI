import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../core/widgets/gradient_button.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _login;

  @override
  void initState() {
    super.initState();
    () async {
      _login = await ref.read(authRepositoryProvider).currentLogin();
      if (mounted) setState(() {});
    }();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(authRepositoryProvider).unlock(_password.text);
      if (!ok) {
        setState(() => _error = 'Неверный пароль');
        return;
      }
      ref.invalidate(isLockedProvider);
      if (mounted) context.go('/entries');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Center(child: AppLogo(size: 88)),
                const SizedBox(height: 28),
                Text('Заблокировано',
                    style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  _login ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  obscureText: true,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 20),
                GradientButton(
                  onPressed: _busy ? null : _submit,
                  loading: _busy,
                  child: const Text('Разблокировать'),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
