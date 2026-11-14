import 'package:common_learn_english/features/settings/data/api_usage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimateTokenCount handles english and chinese', () {
    expect(estimateTokenCount('hello world'), greaterThan(0));
    expect(estimateTokenCount('你好世界'), greaterThanOrEqualTo(4));
  });

  test('pricing for gpt-4o-mini is cheap', () {
    final double cost = ApiUsagePricing.costUsdForTokens(
      model: 'gpt-4o-mini',
      promptTokens: 1000000,
      completionTokens: 0,
    );
    expect(cost, closeTo(0.15, 0.001));
  });

  test('recordChatCompletionResponse prefers usage field', () async {
    final ApiUsageLedger ledger = ApiUsageLedger.instance;
    ledger.setAccountKey('test-usage@example.com');
    await ledger.clearAccount('test-usage@example.com');
    await ledger.recordChatCompletionResponse(
      kind: ApiUsageKind.translation,
      provider: 'OpenAI',
      model: 'gpt-4o-mini',
      responseData: <String, Object?>{
        'usage': <String, Object?>{
          'prompt_tokens': 100,
          'completion_tokens': 50,
        },
      },
    );
    final ApiUsageSnapshot snap = ledger.snapshotForAccount(
      'test-usage@example.com',
    );
    expect(snap.totalTokens, 150);
    expect(snap.totalCostUsd, greaterThan(0));
    await ledger.clearAccount('test-usage@example.com');
  });
}
