import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Categories of billable API work tracked on-device.
enum ApiUsageKind {
  translation,
  wordLookup,
  grammar,
  asr,
  other,
}

extension ApiUsageKindLabel on ApiUsageKind {
  String get labelZh {
    switch (this) {
      case ApiUsageKind.translation:
        return '翻译';
      case ApiUsageKind.wordLookup:
        return '查词';
      case ApiUsageKind.grammar:
        return '语法解析';
      case ApiUsageKind.asr:
        return '语音识别';
      case ApiUsageKind.other:
        return '其他';
    }
  }
}

@immutable
class ApiUsageEvent {
  const ApiUsageEvent({
    required this.id,
    required this.accountKey,
    required this.kind,
    required this.provider,
    required this.model,
    required this.promptTokens,
    required this.completionTokens,
    required this.costUsd,
    required this.atMs,
    this.note = '',
    this.audioSeconds = 0,
  });

  final String id;
  final String accountKey;
  final ApiUsageKind kind;
  final String provider;
  final String model;
  final int promptTokens;
  final int completionTokens;
  final double costUsd;
  final int atMs;
  final String note;
  final double audioSeconds;

  int get totalTokens => promptTokens + completionTokens;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'accountKey': accountKey,
    'kind': kind.name,
    'provider': provider,
    'model': model,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'costUsd': costUsd,
    'atMs': atMs,
    'note': note,
    'audioSeconds': audioSeconds,
  };

  static ApiUsageEvent? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final String id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      return null;
    }
    final String kindName = '${raw['kind'] ?? 'other'}';
    final ApiUsageKind kind = ApiUsageKind.values.firstWhere(
      (ApiUsageKind value) => value.name == kindName,
      orElse: () => ApiUsageKind.other,
    );
    return ApiUsageEvent(
      id: id,
      accountKey: '${raw['accountKey'] ?? 'local'}',
      kind: kind,
      provider: '${raw['provider'] ?? ''}',
      model: '${raw['model'] ?? ''}',
      promptTokens: _asInt(raw['promptTokens']),
      completionTokens: _asInt(raw['completionTokens']),
      costUsd: _asDouble(raw['costUsd']),
      atMs: _asInt(raw['atMs']),
      note: '${raw['note'] ?? ''}',
      audioSeconds: _asDouble(raw['audioSeconds']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
  }

  static double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }
}

@immutable
class ApiUsageSnapshot {
  const ApiUsageSnapshot({
    required this.accountKey,
    required this.events,
  });

  final String accountKey;
  final List<ApiUsageEvent> events;

  int get totalTokens =>
      events.fold<int>(0, (int sum, ApiUsageEvent e) => sum + e.totalTokens);

  int get promptTokens =>
      events.fold<int>(0, (int sum, ApiUsageEvent e) => sum + e.promptTokens);

  int get completionTokens => events.fold<int>(
    0,
    (int sum, ApiUsageEvent e) => sum + e.completionTokens,
  );

  double get totalCostUsd =>
      events.fold<double>(0, (double sum, ApiUsageEvent e) => sum + e.costUsd);

  double get totalAudioSeconds => events.fold<double>(
    0,
    (double sum, ApiUsageEvent e) => sum + e.audioSeconds,
  );

  /// Rough CNY using a fixed FX for display (not a live rate).
  double get totalCostCny => totalCostUsd * ApiUsagePricing.usdToCny;

  Map<ApiUsageKind, double> get costByKind {
    final Map<ApiUsageKind, double> out = <ApiUsageKind, double>{};
    for (final ApiUsageEvent event in events) {
      out[event.kind] = (out[event.kind] ?? 0) + event.costUsd;
    }
    return out;
  }

  Map<ApiUsageKind, int> get tokensByKind {
    final Map<ApiUsageKind, int> out = <ApiUsageKind, int>{};
    for (final ApiUsageEvent event in events) {
      out[event.kind] = (out[event.kind] ?? 0) + event.totalTokens;
    }
    return out;
  }

  Map<ApiUsageKind, double> get audioSecondsByKind {
    final Map<ApiUsageKind, double> out = <ApiUsageKind, double>{};
    for (final ApiUsageEvent event in events) {
      if (event.audioSeconds <= 0) {
        continue;
      }
      out[event.kind] = (out[event.kind] ?? 0) + event.audioSeconds;
    }
    return out;
  }
}

/// Public list prices used only for **estimates** shown in Settings.
class ApiUsagePricing {
  static const double usdToCny = 7.2;

  /// Returns (inputUsdPer1M, outputUsdPer1M).
  static (double, double) llmRates(String model) {
    final String m = model.trim().toLowerCase();
    if (m.contains('gpt-4o-mini') || m.contains('gpt4o-mini')) {
      return (0.15, 0.60);
    }
    if (m.contains('gpt-4o') || m.contains('gpt4o')) {
      return (2.50, 10.0);
    }
    if (m.contains('gpt-4.1-mini') || m.contains('gpt-4.1-nano')) {
      return (0.40, 1.60);
    }
    if (m.contains('gpt-4.1')) {
      return (2.0, 8.0);
    }
    if (m.contains('deepseek')) {
      return (0.27, 1.10);
    }
    if (m.contains('qwen') || m.contains('dashscope')) {
      return (0.40, 1.20);
    }
    if (m.contains('claude') && m.contains('haiku')) {
      return (0.80, 4.0);
    }
    if (m.contains('claude')) {
      return (3.0, 15.0);
    }
    // Conservative default for unknown chat models.
    return (0.50, 1.50);
  }

  /// Bailian / cloud ASR ≈ USD per audio minute (rough public-tier estimate).
  static double asrUsdPerMinute(String model) {
    final String m = model.trim().toLowerCase();
    if (m.contains('qwen') || m.contains('bailian') || m.contains('dashscope')) {
      return 0.006;
    }
    if (m.contains('16k') || m.contains('tencent')) {
      return 0.004;
    }
    return 0.006;
  }

  static double costUsdForTokens({
    required String model,
    required int promptTokens,
    required int completionTokens,
  }) {
    final (double inRate, double outRate) = llmRates(model);
    return promptTokens / 1e6 * inRate + completionTokens / 1e6 * outRate;
  }

  static double costUsdForAudio({
    required String model,
    required double audioSeconds,
  }) {
    if (audioSeconds <= 0) {
      return 0;
    }
    return (audioSeconds / 60.0) * asrUsdPerMinute(model);
  }
}

/// Heuristic token estimate when the provider omits `usage`.
int estimateTokenCount(String text) {
  final String value = text.trim();
  if (value.isEmpty) {
    return 0;
  }
  int cjk = 0;
  int other = 0;
  for (final int unit in value.runes) {
    if ((unit >= 0x4E00 && unit <= 0x9FFF) ||
        (unit >= 0x3400 && unit <= 0x4DBF) ||
        (unit >= 0x3040 && unit <= 0x30FF)) {
      cjk += 1;
    } else if (!RegExp(r'\s').hasMatch(String.fromCharCode(unit))) {
      other += 1;
    }
  }
  // Chinese ≈ 1.2 tok/char; Latin ≈ 1 tok / 4 chars.
  final double estimate = cjk * 1.2 + other / 4.0;
  return math.max(1, estimate.ceil());
}

int estimateMessagesTokens(List<Map<String, String>> messages) {
  int total = 0;
  for (final Map<String, String> message in messages) {
    total += estimateTokenCount(message['content'] ?? '');
    total += 4; // role framing overhead
  }
  return total;
}

/// On-device usage ledger keyed by account email (or `local`).
class ApiUsageLedger extends ChangeNotifier {
  ApiUsageLedger._();

  static final ApiUsageLedger instance = ApiUsageLedger._();

  static const String _storageKey = 'api_usage_ledger_v1';
  static const int _maxEvents = 2000;

  final List<ApiUsageEvent> _events = <ApiUsageEvent>[];
  bool _loaded = false;
  String _accountKey = 'local';

  String get accountKey => _accountKey;

  void setAccountKey(String? emailOrId) {
    final String next = (emailOrId ?? '').trim().isEmpty
        ? 'local'
        : emailOrId!.trim().toLowerCase();
    if (next == _accountKey) {
      return;
    }
    _accountKey = next;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    try {
      final String? raw = Hive.box<String>('prefs').get(_storageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      _events
        ..clear()
        ..addAll(
          decoded
              .map(ApiUsageEvent.fromJson)
              .whereType<ApiUsageEvent>(),
        );
    } catch (_) {}
  }

  ApiUsageSnapshot snapshotForAccount([String? accountKey]) {
    final String key = (accountKey ?? _accountKey).trim().isEmpty
        ? 'local'
        : (accountKey ?? _accountKey);
    final List<ApiUsageEvent> scoped = _events
        .where((ApiUsageEvent e) => e.accountKey == key)
        .toList(growable: false);
    return ApiUsageSnapshot(accountKey: key, events: scoped);
  }

  Future<void> record({
    required ApiUsageKind kind,
    required String provider,
    required String model,
    int? promptTokens,
    int? completionTokens,
    String? promptText,
    String? completionText,
    List<Map<String, String>>? messages,
    double audioSeconds = 0,
    String note = '',
    bool free = false,
  }) async {
    await ensureLoaded();
    int prompt = promptTokens ?? 0;
    int completion = completionTokens ?? 0;
    if (prompt <= 0 && messages != null) {
      prompt = estimateMessagesTokens(messages);
    }
    if (prompt <= 0 && (promptText ?? '').isNotEmpty) {
      prompt = estimateTokenCount(promptText!);
    }
    if (completion <= 0 && (completionText ?? '').isNotEmpty) {
      completion = estimateTokenCount(completionText!);
    }

    double cost = 0;
    if (!free) {
      if (kind == ApiUsageKind.asr) {
        cost = ApiUsagePricing.costUsdForAudio(
          model: model,
          audioSeconds: audioSeconds,
        );
      } else {
        cost = ApiUsagePricing.costUsdForTokens(
          model: model,
          promptTokens: prompt,
          completionTokens: completion,
        );
      }
    }

    final ApiUsageEvent event = ApiUsageEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_events.length}',
      accountKey: _accountKey,
      kind: kind,
      provider: provider,
      model: model,
      promptTokens: prompt,
      completionTokens: completion,
      costUsd: cost,
      atMs: DateTime.now().millisecondsSinceEpoch,
      note: note,
      audioSeconds: audioSeconds,
    );
    _events.add(event);
    while (_events.length > _maxEvents) {
      _events.removeAt(0);
    }
    await _persist();
    notifyListeners();
  }

  /// Prefer official `usage` from OpenAI-compatible JSON when present.
  Future<void> recordChatCompletionResponse({
    required ApiUsageKind kind,
    required String provider,
    required String model,
    required Object? responseData,
    List<Map<String, String>>? messages,
    String? completionText,
    String note = '',
  }) async {
    int? prompt;
    int? completion;
    if (responseData is Map) {
      final Object? usage = responseData['usage'];
      if (usage is Map) {
        prompt = ApiUsageEvent._asInt(usage['prompt_tokens']);
        completion = ApiUsageEvent._asInt(usage['completion_tokens']);
        if (prompt == 0 && completion == 0) {
          prompt = null;
          completion = null;
        }
      }
    }
    await record(
      kind: kind,
      provider: provider,
      model: model,
      promptTokens: prompt,
      completionTokens: completion,
      messages: messages,
      completionText: completionText,
      note: note,
    );
  }

  Future<void> clearAccount([String? accountKey]) async {
    await ensureLoaded();
    final String key = accountKey ?? _accountKey;
    _events.removeWhere((ApiUsageEvent e) => e.accountKey == key);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    await Hive.box<String>('prefs').put(
      _storageKey,
      jsonEncode(_events.map((ApiUsageEvent e) => e.toJson()).toList()),
    );
  }
}
