import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:acp_remote/core/providers/usage_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer createContainer() => ProviderContainer();

  test('reportContext stores figures and fraction', () async {
    final container = createContainer();
    final notifier = container.read(usageTrackerProvider.notifier);

    await Future.delayed(const Duration(milliseconds: 100));

    notifier.reportContext('opencode',
        used: 50000, size: 200000, costAmount: 1.5, costCurrency: 'USD');

    final snap = container.read(usageTrackerProvider).byAgent['opencode']!;
    expect(snap.ctxUsed, 50000);
    expect(snap.ctxSize, 200000);
    expect(snap.contextFraction, closeTo(0.25, 0.0001));
    expect(snap.costAmount, 1.5);
    expect(snap.hasData, isTrue);

    container.dispose();
  });

  test('reportPromptUsage accumulates and ignores zeros', () async {
    final container = createContainer();
    final notifier = container.read(usageTrackerProvider.notifier);

    await Future.delayed(const Duration(milliseconds: 100));

    notifier.reportPromptUsage('cursor', input: 100, output: 20, cached: 5);
    notifier.reportPromptUsage('cursor', input: 50, output: 10);
    notifier.reportPromptUsage('cursor');

    final snap = container.read(usageTrackerProvider).byAgent['cursor']!;
    expect(snap.sessInput, 150);
    expect(snap.sessOutput, 30);
    expect(snap.sessCached, 5);

    container.dispose();
  });

  test('isOverThreshold respects warnPct', () async {
    final container = createContainer();
    final notifier = container.read(usageTrackerProvider.notifier);

    await Future.delayed(const Duration(milliseconds: 100));

    notifier.reportContext('opencode', used: 85000, size: 100000);
    // Default threshold is 80.
    expect(notifier.isOverThreshold('opencode'), isTrue);
    expect(notifier.isOverThreshold('unknown-agent'), isFalse);

    await notifier.setWarnPct(90);
    expect(notifier.isOverThreshold('opencode'), isFalse);

    await notifier.setWarnPct(0); // off
    expect(notifier.isOverThreshold('opencode'), isFalse);

    container.dispose();
  });

  test('snapshots and threshold survive container recreation', () async {
    final first = createContainer();
    final notifier = first.read(usageTrackerProvider.notifier);

    await Future.delayed(const Duration(milliseconds: 100));

    notifier.reportContext('claude', used: 1000, size: 1000000);
    await notifier.setWarnPct(70);
    // Let async persistence land.
    await Future.delayed(const Duration(milliseconds: 100));
    first.dispose();

    final second = createContainer();
    // Touch the provider first so hydration starts, then wait for it.
    second.read(usageTrackerProvider);
    await Future.delayed(const Duration(milliseconds: 200));

    final state = second.read(usageTrackerProvider);
    expect(state.warnPct, 70);
    expect(state.byAgent['claude']!.ctxUsed, 1000);
    expect(state.byAgent['claude']!.ctxSize, 1000000);

    second.dispose();
  });

  test('AgentUsage json round-trip', () {
    const snap = AgentUsage(
      ctxUsed: 1,
      ctxSize: 2,
      costAmount: 0.5,
      costCurrency: 'USD',
      sessInput: 3,
      sessOutput: 4,
      sessCached: 5,
      updatedAt: 6,
    );
    final restored = AgentUsage.fromJson(snap.toJson());
    expect(restored.ctxUsed, 1);
    expect(restored.ctxSize, 2);
    expect(restored.costAmount, 0.5);
    expect(restored.sessInput, 3);
    expect(restored.updatedAt, 6);
  });
}
