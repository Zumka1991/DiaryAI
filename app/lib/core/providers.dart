import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_repository.dart';
import '../features/categories/categories_repository.dart';
import '../features/entries/entries_repository.dart';
import '../features/sync/sync_service.dart';
import 'api/ai_api.dart';
import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/sync_api.dart';
import 'db/database.dart';
import 'storage/secure_storage.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(secureStoreProvider));
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final syncApiProvider = Provider<SyncApi>((ref) => SyncApi(ref.watch(apiClientProvider)));
final aiApiProvider = Provider<AiApi>((ref) => AiApi(ref.watch(apiClientProvider)));

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(secureStoreProvider),
    ref.watch(databaseProvider),
  );
});

final entriesRepositoryProvider = Provider<EntriesRepository>((ref) {
  return EntriesRepository(ref.watch(databaseProvider));
});

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(ref.watch(databaseProvider));
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(syncApiProvider), ref.watch(databaseProvider));
});

/// Есть ли локальный профиль (созданный или восстановленный).
final hasProfileProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).hasProfile();
});

/// Включена ли синхронизация (есть JWT).
final isSyncEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).isSyncEnabled();
});

/// Заблокировано ли приложение (профиль есть, но master_key стёрт).
final isLockedProvider = FutureProvider<bool>((ref) {
  return ref.watch(authRepositoryProvider).isLocked();
});

/// Расшифрованный список записей. Перечитывается через invalidate.
final entriesListProvider = FutureProvider.autoDispose<List<DiaryEntry>>((ref) async {
  final repo = ref.watch(entriesRepositoryProvider);
  final auth = ref.watch(authRepositoryProvider);
  final key = await auth.currentMasterKey();
  if (key == null) return [];
  return repo.list(masterKey: key);
});

final entryProvider =
    FutureProvider.autoDispose.family<DiaryEntry?, String>((ref, id) async {
  final repo = ref.watch(entriesRepositoryProvider);
  final key = await ref.watch(authRepositoryProvider).currentMasterKey();
  if (key == null) return null;
  return repo.get(id, masterKey: key);
});

final categoriesListProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(categoriesRepositoryProvider);
  await repo.ensureDefaults();
  return repo.list();
});
