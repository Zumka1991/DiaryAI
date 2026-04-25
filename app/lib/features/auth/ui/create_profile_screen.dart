import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../core/widgets/gradient_button.dart';

class CreateProfileScreen extends ConsumerStatefulWidget {
  const CreateProfileScreen({super.key});
  @override
  ConsumerState<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends ConsumerState<CreateProfileScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  bool _ack = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final login = _login.text.trim().toLowerCase();
    if (!_validLogin(login)) {
      setState(() => _error = 'Логин: 3-64 символа, a-z 0-9 _ . -');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Пароль минимум 8 символов');
      return;
    }
    if (_password.text != _password2.text) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    if (!_ack) {
      setState(() => _error = 'Подтвердите, что понимаете риск потери пароля');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).createLocalProfile(
            login: login,
            password: _password.text,
          );
      ref.invalidate(hasProfileProvider);
      if (mounted) context.go('/entries');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validLogin(String s) {
    if (s.length < 3 || s.length > 64) return false;
    return RegExp(r'^[a-z0-9._-]+$').hasMatch(s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(title: const Text('Создать дневник')),
      body: GradientBackground(
        child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _login,
                decoration: const InputDecoration(
                  labelText: 'Логин',
                  helperText: 'a-z, 0-9, _ . —. Понадобится позже для синхронизации.',
                ),
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
              TextField(
                controller: _password2,
                decoration: const InputDecoration(labelText: 'Повторите пароль'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        'Восстановить пароль невозможно. Если вы его забудете — все записи будут потеряны без возможности расшифровки. '
                        'Это плата за полное end-to-end шифрование: даже мы не можем прочитать ваши записи.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _ack,
                        onChanged: (v) => setState(() => _ack = v ?? false),
                        title: const Text('Я понимаю и принимаю это'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              GradientButton(
                onPressed: _busy ? null : _submit,
                loading: _busy,
                child: const Text('Создать'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
