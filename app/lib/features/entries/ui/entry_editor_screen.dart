import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import 'package:dio/dio.dart';

import '../../../core/api/ai_api.dart';
import '../../../core/audio/wav_encoder.dart';
import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/gradient_background.dart';
import '../../../core/widgets/gradient_button.dart';
import '../entries_notifier.dart';
import '../entries_repository.dart';

class EntryEditorScreen extends ConsumerStatefulWidget {
  final String? entryId; // null = новая
  const EntryEditorScreen({super.key, this.entryId});
  @override
  ConsumerState<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends ConsumerState<EntryEditorScreen> {
  static const _voiceSampleRate = 16000;
  static const _voiceChannels = 1;

  final _title = TextEditingController();
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordingSub;
  Timer? _recordingTimer;
  final List<Uint8List> _recordingChunks = [];
  DateTime _entryAt = DateTime.now();
  String? _categoryId;
  String _aiComment = '';
  bool _wantAnalyze = false;
  bool _loaded = false;
  bool _busy = false;
  bool _recording = false;
  Duration _recordingDuration = Duration.zero;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    if (widget.entryId == null) {
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingSub?.cancel();
    _recorder.dispose();
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || widget.entryId == null) return;
    try {
      final entry = await ref.read(entryProvider(widget.entryId!).future);
      if (entry == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Запись не найдена. Возможно, нужна синхронизация.',
              ),
            ),
          );
          context.pop();
        }
        return;
      }
      if (mounted) {
        _title.text = entry.title;
        _text.text = entry.text;
        // entry.entryAt хранится как wall-clock UTC. Распаковываем компоненты
        // в local DateTime, чтобы пикеры даты/времени работали корректно.
        final ea = entry.entryAt;
        _entryAt = DateTime(ea.year, ea.month, ea.day, ea.hour, ea.minute);
        _categoryId = entry.categoryId;
        _aiComment = entry.aiComment;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось расшифровать запись: $e')),
        );
        context.pop();
      }
      return;
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty && _title.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Запись пустая')));
      return;
    }
    setState(() {
      _busy = true;
      _busyMessage = 'Сохраняю...';
    });
    try {
      final repo = ref.read(entriesRepositoryProvider);
      final key = await ref.read(authRepositoryProvider).currentMasterKey();
      if (key == null) throw StateError('Сессия не найдена');

      // Сначала сохраняем без ai_comment (или с уже имеющимся).
      final saved = await repo.save(
        masterKey: key,
        id: widget.entryId,
        title: _title.text.trim(),
        text: text,
        entryAt: _entryAt,
        categoryId: _categoryId,
        aiComment: _aiComment,
      );

      // Если стоит галочка — анализируем и пересохраняем с комментарием.
      if (_wantAnalyze) {
        if (mounted) setState(() => _busyMessage = 'Анализирую...');
        try {
          // Контекст: до 5 записей до и до 5 после фокусной, отсортированы хронологически.
          // Так ИИ видит и историю, и то что произошло потом (важно для старых записей).
          final ctxEntries = await repo.contextAround(
            masterKey: key,
            focus: saved,
          );
          final result = await ref
              .read(aiApiProvider)
              .analyze(
                focus: _toAi(saved),
                context: ctxEntries.map(_toAi).toList(),
              );
          await repo.save(
            masterKey: key,
            id: saved.id,
            title: saved.title,
            text: saved.text,
            entryAt: saved.entryAt,
            categoryId: saved.categoryId,
            aiComment: result.analysis,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Анализ готов (${result.used}/${result.dailyLimit} за сегодня)',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Запись сохранена, но анализ не получился: ${_humanError(e)}',
                ),
              ),
            );
          }
        }
      }

      ref.read(entriesNotifierProvider.notifier).refresh();
      if (widget.entryId != null) {
        ref.invalidate(entryProvider(widget.entryId!));
      }
      // Авто-синк (если включён) — фоновый, ошибки игнорируем.
      final syncEnabled = await ref
          .read(authRepositoryProvider)
          .isSyncEnabled();
      if (syncEnabled) {
        ref.read(syncServiceProvider).syncOnce().ignore();
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  AiEntryDto _toAi(DiaryEntry e) => AiEntryDto(
    date: e.entryAt.toUtc().toIso8601String(),
    title: e.title,
    text: e.text,
  );

  Future<void> _toggleVoiceRecording() async {
    if (_busy) return;
    if (_recording) {
      await _stopAndTranscribe();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет доступа к микрофону')),
          );
        }
        return;
      }

      _recordingChunks.clear();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _voiceSampleRate,
          numChannels: _voiceChannels,
        ),
      );
      await _recordingSub?.cancel();
      _recordingSub = stream.listen((chunk) {
        if (chunk.isNotEmpty) _recordingChunks.add(Uint8List.fromList(chunk));
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });
      if (mounted) {
        setState(() {
          _recording = true;
          _recordingDuration = Duration.zero;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось начать запись: ${_humanError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _stopAndTranscribe() async {
    setState(() {
      _busy = true;
      _busyMessage = 'Расшифровываю...';
    });

    try {
      await _recorder.stop();
      _recordingTimer?.cancel();
      await _recordingSub?.cancel();
      _recordingSub = null;

      final chunks = List<Uint8List>.from(_recordingChunks);
      _recordingChunks.clear();
      if (mounted) {
        setState(() {
          _recording = false;
          _recordingDuration = Duration.zero;
        });
      }
      if (chunks.isEmpty) {
        throw StateError('пустая запись');
      }

      final wav = pcm16ToWav(
        chunks: chunks,
        sampleRate: _voiceSampleRate,
        channels: _voiceChannels,
      );
      final text = await ref.read(aiApiProvider).transcribe(audioBytes: wav);
      if (text.isEmpty) {
        throw StateError('модель вернула пустой текст');
      }
      _insertTranscript(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось расшифровать голос: ${_humanError(e)}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
          _recording = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  void _insertTranscript(String transcript) {
    final current = _text.text;
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    final prefix = current.substring(0, start);
    final suffix = current.substring(end);
    final needsLeadingSpace =
        prefix.isNotEmpty && !RegExp(r'\s$').hasMatch(prefix);
    final needsTrailingSpace =
        suffix.isNotEmpty && !RegExp(r'^\s').hasMatch(suffix);
    final insert = [
      if (needsLeadingSpace) ' ',
      transcript.trim(),
      if (needsTrailingSpace) ' ',
    ].join();
    _text.value = TextEditingValue(
      text: '$prefix$insert$suffix',
      selection: TextSelection.collapsed(offset: prefix.length + insert.length),
    );
  }

  Future<void> _delete() async {
    if (widget.entryId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить запись?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(entriesRepositoryProvider).delete(widget.entryId!);
    ref.read(entriesNotifierProvider.notifier).refresh();
    // Если синк включён — сразу же отправляем soft-delete на сервер,
    // чтобы запись пропала и на других устройствах. Ошибки игнорируем
    // (запись помечена dirty, уйдёт при следующем синке).
    final syncEnabled = await ref.read(authRepositoryProvider).isSyncEnabled();
    if (syncEnabled) {
      ref.read(syncServiceProvider).syncOnce().ignore();
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final categoriesAsync = ref.watch(categoriesListProvider);
    final df = DateFormat('d MMMM, HH:mm', 'ru');
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entryId == null ? 'Новая запись' : 'Запись'),
        actions: [
          if (widget.entryId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: GradientBackground(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                            label: Text(df.format(_entryAt)),
                            onPressed: _busy ? null : _pickDateTime,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildCategoryDropdown(
                              categoriesAsync.valueOrNull ?? [],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _title,
                        decoration: const InputDecoration(
                          hintText: 'Заголовок (необязательно)',
                          border: InputBorder.none,
                          filled: false,
                        ),
                        style: theme.textTheme.titleLarge,
                        enabled: !_busy,
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      _buildVoiceToolbar(theme),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _text,
                        maxLines: 16,
                        minLines: 10,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: 'О чём думаете?',
                          border: InputBorder.none,
                          filled: false,
                        ),
                        enabled: !_busy,
                      ),
                      if (_aiComment.isNotEmpty) _buildAiCommentCard(theme),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _wantAnalyze,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _wantAnalyze = v ?? false),
                        title: const Text(
                          'Проанализировать ИИ после сохранения',
                        ),
                        subtitle: const Text(
                          'Учитывает 10 последних записей. Лимит: 3/день.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 8),
                      GradientButton(
                        onPressed: _busy ? null : _save,
                        loading: _busy,
                        child: Text(
                          _busy ? (_busyMessage ?? 'Сохраняю...') : 'Сохранить',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildAiCommentCard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.aiCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.lavender.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Анализ ИИ',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SelectableText(
              _aiComment,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceToolbar(ThemeData theme) {
    final minutes = _recordingDuration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = _recordingDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: _recording
              ? 'Остановить и расшифровать'
              : 'Надиктовать текст',
          onPressed: _busy ? null : _toggleVoiceRecording,
          icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_none_rounded),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _recording ? 'Запись $minutes:$seconds' : 'Голос в текст',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _recording
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: _recording ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(List categories) {
    return DropdownButtonFormField<String?>(
      initialValue: _categoryId,
      decoration: const InputDecoration(labelText: 'Категория'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Без категории'),
        ),
        for (final c in categories)
          DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
      ],
      onChanged: _busy ? null : (v) => setState(() => _categoryId = v),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _entryAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_entryAt),
    );
    if (time == null) return;
    setState(() {
      _entryAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }
}

String _humanError(Object e) {
  if (e is DioException) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    if (code == 429) {
      final used = (body is Map ? body['used'] : null) ?? '';
      final lim = (body is Map ? body['daily_limit'] : null) ?? 3;
      return 'Дневной лимит ИИ исчерпан ($used/$lim). Завтра — снова доступно.';
    }
    if (code == 503) return 'ИИ временно недоступен';
    if (code == 502) return 'Ошибка модели OpenRouter';
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Нет соединения с сервером';
    }
    if (body is Map && body['error'] != null) return body['error'].toString();
  }
  final s = e.toString();
  return s.length > 200 ? '${s.substring(0, 200)}…' : s;
}
