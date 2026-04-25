import 'dart:convert';

import 'api_client.dart';

class AiEntryDto {
  final String date;       // RFC3339
  final String title;
  final String? category;
  final String text;
  AiEntryDto({required this.date, required this.title, required this.text, this.category});

  Map<String, dynamic> toJson() => {
        'date': date,
        'title': title,
        if (category != null) 'category': category,
        'text': text,
      };
}

class AnalyzeResult {
  final String analysis;
  final int used;
  final int dailyLimit;
  AnalyzeResult({required this.analysis, required this.used, required this.dailyLimit});
}

class AiApi {
  final ApiClient _api;
  AiApi(this._api);

  Future<AnalyzeResult> analyze({
    required AiEntryDto focus,
    required List<AiEntryDto> context,
    String? model,
  }) async {
    final r = await _api.dio.post('/ai/analyze', data: jsonEncode({
      'focus_entry': focus.toJson(),
      'context_entries': context.map((e) => e.toJson()).toList(),
      if (model != null) 'model': model,
    }));
    return AnalyzeResult(
      analysis: r.data['analysis'] as String,
      used: (r.data['used'] as num?)?.toInt() ?? 0,
      dailyLimit: (r.data['daily_limit'] as num?)?.toInt() ?? 3,
    );
  }
}
