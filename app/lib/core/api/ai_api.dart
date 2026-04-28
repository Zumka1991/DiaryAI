import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

class AiEntryDto {
  final String date; // RFC3339
  final String title;
  final String? category;
  final String text;
  AiEntryDto({
    required this.date,
    required this.title,
    required this.text,
    this.category,
  });

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{'date': date, 'title': title, 'text': text};
    if (category != null) data['category'] = category;
    return data;
  }
}

class AnalyzeResult {
  final String analysis;
  final int used;
  final int dailyLimit;
  AnalyzeResult({
    required this.analysis,
    required this.used,
    required this.dailyLimit,
  });
}

class AiApi {
  final ApiClient _api;
  AiApi(this._api);

  Future<AnalyzeResult> analyze({
    required AiEntryDto focus,
    required List<AiEntryDto> context,
    String? model,
  }) async {
    final payload = <String, dynamic>{
      'focus_entry': focus.toJson(),
      'context_entries': context.map((e) => e.toJson()).toList(),
    };
    if (model != null) payload['model'] = model;
    final r = await _api.dio.post('/ai/analyze', data: jsonEncode(payload));
    return AnalyzeResult(
      analysis: r.data['analysis'] as String,
      used: (r.data['used'] as num?)?.toInt() ?? 0,
      dailyLimit: (r.data['daily_limit'] as num?)?.toInt() ?? 3,
    );
  }

  Future<String> transcribe({
    required Uint8List audioBytes,
    String filename = 'voice.wav',
    String? model,
  }) async {
    final form = FormData.fromMap({
      'audio': MultipartFile.fromBytes(audioBytes, filename: filename),
    });
    if (model != null) form.fields.add(MapEntry('model', model));
    final r = await _api.dio.post(
      '/ai/transcribe',
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    return (r.data['text'] as String?)?.trim() ?? '';
  }
}
