import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'features/auth/ui/create_profile_screen.dart';
import 'features/auth/ui/lock_screen.dart';
import 'features/auth/ui/restore_screen.dart';
import 'features/auth/ui/welcome_screen.dart';
import 'features/categories/ui/categories_screen.dart';
import 'features/entries/ui/entries_list_screen.dart';
import 'features/entries/ui/entry_editor_screen.dart';
import 'features/settings/ui/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/entries',
    redirect: (context, state) async {
      final repo = ref.read(authRepositoryProvider);
      final hasProfile = await repo.hasProfile();
      final loc = state.matchedLocation;

      const publicRoutes = {
        '/welcome',
        '/create-profile',
        '/restore',
        '/settings/server',
      };

      if (!hasProfile) {
        return publicRoutes.contains(loc) ? null : '/welcome';
      }

      // Профиль есть. Проверим блокировку.
      final locked = await repo.isLocked();
      if (locked) {
        return loc == '/lock' ? null : '/lock';
      }

      // Разблокирован. Не пускаем обратно на стартовые экраны.
      if (loc == '/welcome' || loc == '/create-profile' || loc == '/restore' || loc == '/lock') {
        return '/entries';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/create-profile', builder: (_, _) => const CreateProfileScreen()),
      GoRoute(path: '/restore', builder: (_, _) => const RestoreScreen()),
      GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),
      GoRoute(path: '/entries', builder: (_, _) => const EntriesListScreen()),
      GoRoute(path: '/entries/new', builder: (_, _) => const EntryEditorScreen()),
      GoRoute(
        path: '/entries/:id',
        builder: (_, s) => EntryEditorScreen(entryId: s.pathParameters['id']),
      ),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/server', builder: (_, _) => const ServerSettingsScreen()),
    ],
  );
});
