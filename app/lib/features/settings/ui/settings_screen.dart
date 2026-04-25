import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../auth/auth_repository.dart';
import '../../entries/entries_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncAsync = ref.watch(isSyncEnabledProvider);
    final loginFut = ref.watch(authRepositoryProvider).currentLogin();

    return Scaffold(

      appBar: AppBar(title: const Text('Настройки')),
      body: GradientBackground(
        child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          FutureBuilder<String?>(
            future: loginFut,
            builder: (_, s) => ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Профиль'),
              subtitle: Text(s.data ?? '...'),
            ),
          ),
          const Divider(),
          syncAsync.when(
            loading: () => const ListTile(
              leading: Icon(Icons.cloud_outlined),
              title: Text('Синхронизация'),
              subtitle: Text('...'),
            ),
            error: (e, _) => ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Синхронизация'),
              subtitle: Text('$e'),
            ),
            data: (enabled) => SwitchListTile(
              secondary: Icon(enabled ? Icons.cloud_done_outlined : Icons.cloud_outlined),
              title: const Text('Синхронизация с облаком'),
              subtitle: Text(
                enabled
                    ? 'Включена. Записи синхронизируются между устройствами в зашифрованном виде.'
                    : 'Выключена. Дневник работает только на этом устройстве.',
              ),
              value: enabled,
              onChanged: (v) async {
                if (v) {
                  await _enableSync(context, ref);
                } else {
                  await _disableSync(context, ref);
                }
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Адрес сервера'),
            onTap: () => context.push('/settings/server'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error),
            title: const Text('Удалить с этого устройства'),
            subtitle: const Text(
              'Сотрёт ключи, JWT и локальную БД. Записи на сервере останутся, '
              'но без пароля их не открыть.',
            ),
            onTap: () => _wipe(context, ref),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Future<void> _enableSync(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref.read(authRepositoryProvider).enableSync();
      await ref.refresh(isSyncEnabledProvider.future); // ignore: unused_result
      switch (res) {
        case EnableSyncResult.registered:
        case EnableSyncResult.loggedIn:
          // Сразу делаем первый синк, чтобы записи поехали на сервер.
          messenger.showSnackBar(const SnackBar(content: Text('Синхронизация...')));
          try {
            final r = await ref.read(syncServiceProvider).syncOnce();
            ref.read(entriesNotifierProvider.notifier).refresh();
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(
              content: Text(res == EnableSyncResult.registered
                  ? 'Аккаунт создан. Отправлено ${r.pushed} записей.'
                  : 'Подключено. Получено ${r.pulled}, отправлено ${r.pushed} записей.'),
            ));
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('Подключено, но синк упал: $e')));
          }
        case EnableSyncResult.conflict:
          if (!context.mounted) return;
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Логин занят'),
              content: const Text(
                'На сервере уже есть аккаунт с таким логином, и он защищён другим паролем. '
                'Выберите другой логин (создайте новый профиль) или восстановите тот аккаунт через "У меня уже есть аккаунт".',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            ),
          );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось включить синк: $e')));
    }
  }

  Future<void> _disableSync(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).disableSync();
    await ref.refresh(isSyncEnabledProvider.future);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Синхронизация выключена')),
      );
    }
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить с устройства?'),
        content: const Text(
          'Все локальные данные и ключ будут удалены. Если синхронизация была включена, '
          'записи останутся на сервере и их можно будет восстановить через логин+пароль.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authRepositoryProvider).wipeDevice();
    ref.invalidate(hasProfileProvider);
    ref.invalidate(isSyncEnabledProvider);
    if (context.mounted) context.go('/welcome');
  }
}

class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});
  @override
  ConsumerState<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  final _ctl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    () async {
      _ctl.text = await ref.read(secureStoreProvider).getServerUrl();
      if (mounted) setState(() => _loaded = true);
    }();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: AppBar(title: const Text('Сервер')),
      body: GradientBackground(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _ctl,
                        decoration: const InputDecoration(
                          labelText: 'URL',
                          helperText:
                              'http://localhost:8090 (десктоп), http://10.0.2.2:8090 (Android-эмулятор), '
                              'https://api.diaryai.ru (продакшн)',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 20),
                      GradientButton(
                        onPressed: () async {
                          await ref.read(secureStoreProvider).setServerUrl(_ctl.text.trim());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Сохранено')),
                            );
                          }
                        },
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
