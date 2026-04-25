import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/gradient_background.dart';
import '../entries_notifier.dart';
import '../entries_repository.dart';

class EntriesListScreen extends ConsumerStatefulWidget {
  const EntriesListScreen({super.key});

  @override
  ConsumerState<EntriesListScreen> createState() => _EntriesListScreenState();
}

class _EntriesListScreenState extends ConsumerState<EntriesListScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _searchMode = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      ref.read(entriesNotifierProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(entriesNotifierProvider);
    final categoriesAsync = ref.watch(categoriesListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _searchMode
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Поиск по записям...',
                  border: InputBorder.none,
                  filled: false,
                ),
                style: theme.textTheme.titleMedium,
                onChanged: (v) =>
                    ref.read(entriesNotifierProvider.notifier).setQuery(v),
              )
            : const Text('DiaryAI'),
        actions: [
          IconButton(
            icon: Icon(_searchMode ? Icons.close : Icons.search),
            tooltip: _searchMode ? 'Закрыть поиск' : 'Поиск',
            onPressed: () {
              setState(() {
                _searchMode = !_searchMode;
                if (!_searchMode) {
                  _search.clear();
                  ref.read(entriesNotifierProvider.notifier).setQuery('');
                }
              });
            },
          ),
          if (!_searchMode) ...[
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Заблокировать',
              onPressed: () async {
                await ref.read(authRepositoryProvider).lock();
                ref.invalidate(isLockedProvider);
                if (context.mounted) context.go('/lock');
              },
            ),
            IconButton(
              icon: const Icon(Icons.cloud_sync_outlined),
              tooltip: 'Синхронизация',
              onPressed: () => _sync(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Категории',
              onPressed: () => context.push('/categories'),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _buildBody(context, state, categoriesAsync.valueOrNull ?? []),
        ),
      ),
      floatingActionButton: _searchMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/entries/new'),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Запись'),
            ),
    );
  }

  Widget _buildBody(BuildContext context, EntriesState state, List categories) {
    if (state.loading && state.visible.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.visible.isEmpty) {
      return state.query.isNotEmpty
          ? _NoResults(query: state.query)
          : const _EmptyState();
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: state.visible.length + (state.hasMore && state.query.isEmpty ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i >= state.visible.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final e = state.visible[i];
        final cat = categories.where((c) => c.id == e.categoryId).firstOrNull;
        return _EntryCard(
          entry: e,
          categoryName: cat?.name,
          categoryColor: cat?.color,
          highlightQuery: state.query,
        );
      },
    );
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final syncEnabled = await ref.read(authRepositoryProvider).isSyncEnabled();
    if (!syncEnabled) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Синхронизация выключена. Включить в настройках?'),
        action: SnackBarAction(
          label: 'Открыть',
          onPressed: () => GoRouter.of(context).push('/settings'),
        ),
      ));
      return;
    }
    try {
      final r = await ref.read(syncServiceProvider).syncOnce();
      await ref.read(entriesNotifierProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(
        content: Text('Синхронизировано: получено ${r.pulled}, отправлено ${r.pushed}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ошибка синка: $e')));
    }
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Ничего не найдено', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('по запросу "$query"',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.lavender.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.edit_note_outlined, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Чистая страница',
                style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Нажмите + чтобы записать первую мысль.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final DiaryEntry entry;
  final String? categoryName;
  final int? categoryColor;
  final String highlightQuery;
  const _EntryCard({
    required this.entry,
    this.categoryName,
    this.categoryColor,
    this.highlightQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMMM, HH:mm', 'ru');
    final preview = _previewText(entry.text, highlightQuery);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasAi = entry.aiComment.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => GoRouter.of(context).push('/entries/${entry.id}'),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer.withValues(alpha: isDark ? 0.85 : 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(df.format(entry.entryAt),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const Spacer(),
                    if (hasAi) ...[
                      Icon(Icons.auto_awesome,
                          size: 14, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
                      const SizedBox(width: 8),
                    ],
                    if (categoryName != null) _CategoryChip(name: categoryName!, color: categoryColor),
                  ],
                ),
                if (entry.title.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(entry.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                ],
                const SizedBox(height: 6),
                Text(
                  preview.isEmpty ? '(пусто)' : preview,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String name;
  final int? color;
  const _CategoryChip({required this.name, this.color});

  @override
  Widget build(BuildContext context) {
    final c = Color(color ?? 0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(name, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _GradientFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _GradientFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.lavender.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Запись',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Превью текста: если есть поисковый запрос — показываем фрагмент вокруг совпадения,
/// иначе — первые ~200 символов.
String _previewText(String text, String query) {
  const maxLen = 220;
  if (text.isEmpty) return '';
  if (query.isEmpty) {
    return text.length > maxLen ? '${text.substring(0, maxLen)}…' : text;
  }
  final lower = text.toLowerCase();
  final i = lower.indexOf(query.toLowerCase());
  if (i < 0) {
    return text.length > maxLen ? '${text.substring(0, maxLen)}…' : text;
  }
  // Окно ±100 символов вокруг совпадения.
  final start = (i - 100).clamp(0, text.length);
  final end = (i + query.length + 120).clamp(0, text.length);
  final snippet = text.substring(start, end);
  return '${start > 0 ? '…' : ''}$snippet${end < text.length ? '…' : ''}';
}
