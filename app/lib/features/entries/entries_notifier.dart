import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'entries_repository.dart';

class EntriesState {
  final List<DiaryEntry> visible;   // что показываем сейчас (с учётом фильтра)
  final int totalCount;             // всего записей в БД (без deleted)
  final int loadedCount;            // сколько подгружено страницами
  final bool hasMore;
  final bool loading;               // первичная или подгрузка следующей страницы
  final String query;
  final bool searchAllLoaded;       // загружены ли все записи для поиска

  const EntriesState({
    this.visible = const [],
    this.totalCount = 0,
    this.loadedCount = 0,
    this.hasMore = true,
    this.loading = false,
    this.query = '',
    this.searchAllLoaded = false,
  });

  EntriesState copyWith({
    List<DiaryEntry>? visible,
    int? totalCount,
    int? loadedCount,
    bool? hasMore,
    bool? loading,
    String? query,
    bool? searchAllLoaded,
  }) {
    return EntriesState(
      visible: visible ?? this.visible,
      totalCount: totalCount ?? this.totalCount,
      loadedCount: loadedCount ?? this.loadedCount,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      query: query ?? this.query,
      searchAllLoaded: searchAllLoaded ?? this.searchAllLoaded,
    );
  }
}

class EntriesNotifier extends Notifier<EntriesState> {
  static const _pageSize = 30;

  // Кеш всех расшифрованных записей — наполняется при первом поиске
  // или когда дошли до конца через пагинацию.
  List<DiaryEntry> _allCache = [];

  @override
  EntriesState build() {
    // Первичная загрузка стартует асинхронно.
    Future.microtask(refresh);
    return const EntriesState(loading: true);
  }

  /// Полный сброс: перезагружает первую страницу.
  Future<void> refresh() async {
    _allCache = [];
    state = const EntriesState(loading: true);
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final repo = ref.read(entriesRepositoryProvider);
    final key = await ref.read(authRepositoryProvider).currentMasterKey();
    if (key == null) {
      state = const EntriesState();
      return;
    }
    final total = await repo.count();
    final page = await repo.listPage(masterKey: key, offset: 0, limit: _pageSize);
    state = EntriesState(
      visible: page,
      totalCount: total,
      loadedCount: page.length,
      hasMore: page.length < total,
      loading: false,
    );
  }

  /// Подгрузить следующую страницу (только когда нет активного поиска).
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.query.isNotEmpty) return;
    state = state.copyWith(loading: true);
    final repo = ref.read(entriesRepositoryProvider);
    final key = await ref.read(authRepositoryProvider).currentMasterKey();
    if (key == null) {
      state = state.copyWith(loading: false);
      return;
    }
    final next = await repo.listPage(
      masterKey: key,
      offset: state.loadedCount,
      limit: _pageSize,
    );
    final newLoaded = state.loadedCount + next.length;
    state = state.copyWith(
      visible: [...state.visible, ...next],
      loadedCount: newLoaded,
      hasMore: newLoaded < state.totalCount,
      loading: false,
    );
  }

  /// Установить поисковый запрос. Пустая строка → выйти из поиска.
  Future<void> setQuery(String q) async {
    final query = q.trim();
    if (query == state.query) return;

    if (query.isEmpty) {
      // Выходим из поиска — возвращаем пагинированный вид.
      state = state.copyWith(query: '', loading: true);
      await _loadFirstPage();
      return;
    }

    // Если ещё не загрузили все записи — загружаем разово в кеш.
    if (!state.searchAllLoaded) {
      state = state.copyWith(query: query, loading: true);
      await _ensureAllLoaded();
    } else {
      state = state.copyWith(query: query);
    }
    _applyFilter();
  }

  Future<void> _ensureAllLoaded() async {
    final repo = ref.read(entriesRepositoryProvider);
    final key = await ref.read(authRepositoryProvider).currentMasterKey();
    if (key == null) return;
    final total = await repo.count();
    _allCache = await repo.listPage(masterKey: key, offset: 0, limit: total);
    state = state.copyWith(
      searchAllLoaded: true,
      totalCount: total,
      loading: false,
    );
  }

  void _applyFilter() {
    final q = state.query.toLowerCase();
    final filtered = _allCache.where((e) {
      return e.title.toLowerCase().contains(q) || e.text.toLowerCase().contains(q);
    }).toList();
    state = state.copyWith(visible: filtered, loading: false);
  }
}

final entriesNotifierProvider =
    NotifierProvider<EntriesNotifier, EntriesState>(EntriesNotifier.new);
