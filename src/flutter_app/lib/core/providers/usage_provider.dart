import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

/// Per-agent usage snapshot. Context figures come from `usage_update`
/// frames; token totals accumulate from prompt-result `usage`.
class AgentUsage {
  final int? ctxUsed;
  final int? ctxSize;
  final num? costAmount;
  final String? costCurrency;
  final int sessInput;
  final int sessOutput;
  final int sessCached;
  final int updatedAt;

  const AgentUsage({
    this.ctxUsed,
    this.ctxSize,
    this.costAmount,
    this.costCurrency,
    this.sessInput = 0,
    this.sessOutput = 0,
    this.sessCached = 0,
    this.updatedAt = 0,
  });

  bool get hasData =>
      ctxUsed != null ||
      sessInput > 0 ||
      sessOutput > 0 ||
      costAmount != null;

  /// 0..1 fraction of the context window used, or null when unknown.
  double? get contextFraction {
    if (ctxUsed == null || ctxSize == null || ctxSize! <= 0) return null;
    return (ctxUsed! / ctxSize!).clamp(0.0, 1.0);
  }

  AgentUsage copyWith({
    int? ctxUsed,
    int? ctxSize,
    num? costAmount,
    String? costCurrency,
    int? sessInput,
    int? sessOutput,
    int? sessCached,
    int? updatedAt,
  }) {
    return AgentUsage(
      ctxUsed: ctxUsed ?? this.ctxUsed,
      ctxSize: ctxSize ?? this.ctxSize,
      costAmount: costAmount ?? this.costAmount,
      costCurrency: costCurrency ?? this.costCurrency,
      sessInput: sessInput ?? this.sessInput,
      sessOutput: sessOutput ?? this.sessOutput,
      sessCached: sessCached ?? this.sessCached,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        if (ctxUsed != null) 'ctxUsed': ctxUsed,
        if (ctxSize != null) 'ctxSize': ctxSize,
        if (costAmount != null) 'costAmount': costAmount,
        if (costCurrency != null) 'costCurrency': costCurrency,
        'sessInput': sessInput,
        'sessOutput': sessOutput,
        'sessCached': sessCached,
        'updatedAt': updatedAt,
      };

  factory AgentUsage.fromJson(Map<String, dynamic> json) => AgentUsage(
        ctxUsed: (json['ctxUsed'] as num?)?.toInt(),
        ctxSize: (json['ctxSize'] as num?)?.toInt(),
        costAmount: json['costAmount'] as num?,
        costCurrency: json['costCurrency'] as String?,
        sessInput: (json['sessInput'] as num?)?.toInt() ?? 0,
        sessOutput: (json['sessOutput'] as num?)?.toInt() ?? 0,
        sessCached: (json['sessCached'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class UsageState {
  final Map<String, AgentUsage> byAgent;
  final int warnPct;

  const UsageState({this.byAgent = const {}, this.warnPct = 80});

  UsageState copyWith({Map<String, AgentUsage>? byAgent, int? warnPct}) {
    return UsageState(
      byAgent: byAgent ?? this.byAgent,
      warnPct: warnPct ?? this.warnPct,
    );
  }
}

/// Central usage store, keyed by agent id so every agent gets its own
/// numbers. Fed by chat sessions; surfaced in Settings and the model
/// chip sheet. Persisted so it survives app restarts.
class UsageTracker extends StateNotifier<UsageState> {
  final Ref _ref;
  bool _warnTouched = false;

  UsageTracker(this._ref) : super(const UsageState()) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await _ref.read(preferencesServiceProvider.future);
      final stored = prefs.getUsageSnapshots();
      final disk = <String, AgentUsage>{};
      stored.forEach((agentId, raw) {
        try {
          disk[agentId] = AgentUsage.fromJson(raw);
        } catch (_) {}
      });
      if (!mounted) return;
      // Merge with live-wins: hydrate may complete after reports were
      // already recorded this session and must not clobber them.
      state = state.copyWith(
        byAgent: {...disk, ...state.byAgent},
        warnPct: _warnTouched ? state.warnPct : prefs.getUsageWarnPct(),
      );
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await _ref.read(preferencesServiceProvider.future);
      await prefs.setUsageSnapshots(
        state.byAgent.map((k, v) => MapEntry(k, v.toJson())),
      );
    } catch (_) {}
  }

  void reportContext(
    String agentId, {
    int? used,
    int? size,
    num? costAmount,
    String? costCurrency,
  }) {
    final prev = state.byAgent[agentId] ?? const AgentUsage();
    final next = prev.copyWith(
      ctxUsed: used ?? prev.ctxUsed,
      ctxSize: size ?? prev.ctxSize,
      costAmount: costAmount ?? prev.costAmount,
      costCurrency: (costCurrency != null && costCurrency.isNotEmpty)
          ? costCurrency
          : prev.costCurrency,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(
      byAgent: {...state.byAgent, agentId: next},
    );
    _persist();
  }

  void reportPromptUsage(
    String agentId, {
    int input = 0,
    int output = 0,
    int cached = 0,
  }) {
    if (input <= 0 && output <= 0 && cached <= 0) return;
    final prev = state.byAgent[agentId] ?? const AgentUsage();
    final next = prev.copyWith(
      sessInput: prev.sessInput + input,
      sessOutput: prev.sessOutput + output,
      sessCached: prev.sessCached + cached,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(
      byAgent: {...state.byAgent, agentId: next},
    );
    _persist();
  }

  Future<void> setWarnPct(int pct) async {
    _warnTouched = true;
    state = state.copyWith(warnPct: pct);
    try {
      final prefs = await _ref.read(preferencesServiceProvider.future);
      await prefs.setUsageWarnPct(pct);
    } catch (_) {}
  }

  /// True when the agent's context usage meets/exceeds the warning
  /// threshold. A threshold of 0 means "off".
  bool isOverThreshold(String agentId) {
    if (state.warnPct <= 0) return false;
    final fraction = state.byAgent[agentId]?.contextFraction;
    if (fraction == null) return false;
    return fraction * 100 >= state.warnPct;
  }
}

final usageTrackerProvider =
    StateNotifierProvider<UsageTracker, UsageState>((ref) {
  return UsageTracker(ref);
});
