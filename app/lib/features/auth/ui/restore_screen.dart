import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../core/widgets/gradient_button.dart';

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});
  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).restoreFromServer(
            login: _login.text.trim().toLowerCase(),
            password: _password.text,
          );
      // Сразу качаем все записи с сервера, чтобы юзер увидел наполненный дневник.
      try {
        await ref.read(syncServiceProvider).syncOnce();
      } catch (_) {
        // Если синк не пройдёт — не страшно, можно повторить из UI.
      }
      ref.invalidate(hasProfileProvider);
      ref.invalidate(isSyncEnabledProvider);
      if (mounted) context.go('/entries');
    } catch (e) {
      setState(() => _error = _humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(title: const Text('Восстановить аккаунт')),
      body: GradientBackground(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Войдите в существующий аккаунт. Записи будут скачаны с сервера и расшифрованы вашим паролем.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _login,
                decoration: const InputDecoration(labelText: 'Логин'),
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Пароль'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              GradientButton(
                onPressed: _busy ? null : _submit,
                loading: _busy,
                child: const Text('Войти'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => context.push('/settings/server'),
                child: const Text('Адрес сервера'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

String _humanError(Object e) {
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code == 401) return 'Неверный логин или пароль';
    if (code == 400) return 'Некорректные данные';
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Нет соединения с сервером. Проверьте адрес в настройках.';
    }
    final body = e.response?.data;
    if (body is Map && body['error'] != null) return body['error'].toString();
  }
  return e.toString();
}
