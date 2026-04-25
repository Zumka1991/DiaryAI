import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/gradient_background.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyn = ref.watch(categoriesListProvider);
    return Scaffold(

      appBar: AppBar(title: const Text('Категории')),
      body: GradientBackground(
        child: SafeArea(
          child: asyn.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => ListView(
              children: [
                for (final c in list)
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Color(c.color), radius: 10),
                    title: Text(c.name),
                    trailing: PopupMenuButton<String>(
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                      onSelected: (v) async {
                        final repo = ref.read(categoriesRepositoryProvider);
                        if (v == 'rename') {
                          final name = await _prompt(context, 'Новое название', initial: c.name);
                          if (name != null && name.isNotEmpty) {
                            await repo.rename(c.id, name);
                            ref.invalidate(categoriesListProvider);
                          }
                        } else if (v == 'delete') {
                          await repo.delete(c.id);
                          ref.invalidate(categoriesListProvider);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.lavender.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: () async {
            final name = await _prompt(context, 'Название категории');
            if (name != null && name.isNotEmpty) {
              await ref.read(categoriesRepositoryProvider).add(name);
              ref.invalidate(categoriesListProvider);
            }
          },
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, {String initial = ''}) async {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}
