import 'dart:convert';

import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/shared/domain/sentence_grammar_analysis.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/player/presentation/widgets/ai_grammar_analysis_sheet.dart';

void main() {
  group('analyzeSentenceGrammar', () {
    test('parses JSON grammar analysis from chat completions', () async {
      final LearningSettingsState settings = LearningSettingsState.defaults()
          .copyWith(
            translationProvider: 'DeepSeek',
            translationApiKey: 'test-key',
            translationBaseUrl: 'https://api.deepseek.com',
            translationModel: 'deepseek-v4-flash',
          );
      final WordLookupService service = WordLookupService(
        httpRequestOverride:
            ({
              required BaseOptions options,
              required String method,
              required String path,
              Map<String, dynamic>? queryParameters,
              Object? data,
            }) async {
              expect(method, 'POST');
              expect(path, '/chat/completions');
              final Map<String, dynamic> body = data! as Map<String, dynamic>;
              final List<Map<String, String>> messages =
                  body['messages'] as List<Map<String, String>>;
              expect(messages.first['role'], 'system');
              expect(messages.last['content'], contains('I have been waiting'));
              expect(messages.last['content'], contains('我一直在等'));
              return Response<dynamic>(
                requestOptions: RequestOptions(path: path),
                data: <String, dynamic>{
                  'choices': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'message': <String, dynamic>{
                        'content':
                            '```json\n${jsonEncode(<String, dynamic>{
                              'sentence': 'I have been waiting for you.',
                              'translationCn': '我一直在等你。',
                              'structureCn': '主语 + 现在完成进行时 + 介词短语',
                              'grammarPoints': <Map<String, String>>[
                                <String, String>{
                                  'title': '现在完成进行时',
                                  'explanation': '强调动作从过去持续到现在。',
                                },
                              ],
                              'keyPhrases': <Map<String, String>>[
                                <String, String>{
                                  'phrase': 'wait for',
                                  'explanation': '等待某人/某事。',
                                },
                              ],
                              'paraphraseEn': 'I have been expecting you.',
                              'learningTipCn': '注意 have been + doing 的搭配。',
                            })}\n```',
                      },
                    },
                  ],
                },
              );
            },
      );

      final SentenceGrammarAnalysis analysis = await service
          .analyzeSentenceGrammar(
            sentence: 'I have been waiting for you.',
            chinese: '我一直在等你。',
            settings: settings,
          );

      expect(analysis.isAvailable, isTrue);
      expect(analysis.structureCn, contains('现在完成进行时'));
      expect(analysis.grammarPoints, hasLength(1));
      expect(analysis.keyPhrases.first.phrase, 'wait for');
      expect(analysis.paraphraseEn, 'I have been expecting you.');
      expect(analysis.sourceLabel, 'DeepSeek');
    });

    test('rejects direct machine-translation providers', () async {
      final SentenceGrammarAnalysis analysis = await const WordLookupService()
          .analyzeSentenceGrammar(
            sentence: 'Hello there.',
            settings: LearningSettingsState.defaults().copyWith(
              translationProvider: 'Google 翻译',
              translationApiKey: 'test-key',
            ),
          );
      expect(analysis.isAvailable, isFalse);
      expect(analysis.errorMessage, contains('AI 对话模型'));
    });

    test('asks for API setup when key is missing', () async {
      final SentenceGrammarAnalysis analysis = await const WordLookupService()
          .analyzeSentenceGrammar(
            sentence: 'Hello there.',
            settings: LearningSettingsState.defaults(),
          );
      expect(analysis.isAvailable, isFalse);
      expect(analysis.errorMessage, contains('设置'));
    });
  });

  testWidgets('grammar sheet shows loading then analysis sections', (
    WidgetTester tester,
  ) async {
    final WordLookupService service = WordLookupService(
      httpRequestOverride:
          ({
            required BaseOptions options,
            required String method,
            required String path,
            Map<String, dynamic>? queryParameters,
            Object? data,
          }) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              data: <String, dynamic>{
                'choices': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'message': <String, dynamic>{
                      'content': jsonEncode(<String, dynamic>{
                        'sentence': 'She may have left already.',
                        'translationCn': '她可能已经离开了。',
                        'structureCn': '情态动词 + 完成式',
                        'grammarPoints': <Map<String, String>>[
                          <String, String>{
                            'title': 'may have + 过去分词',
                            'explanation': '表示对过去情况的推测。',
                          },
                        ],
                        'keyPhrases': <Map<String, String>>[],
                        'paraphraseEn': 'Maybe she already left.',
                        'learningTipCn': 'may have 不等于 must have。',
                      }),
                    },
                  },
                ],
              },
            );
          },
    );

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          wordLookupServiceProvider.overrideWithValue(service),
          learningSettingsProvider.overrideWith(
            _GrammarSettingsNotifier.new,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AiGrammarAnalysisSheet(
              english: 'She may have left already.',
              chinese: '她可能已经离开了。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在分析句子结构与语法点…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('句子结构'), findsOneWidget);
    expect(find.text('语法要点'), findsOneWidget);
    expect(find.textContaining('情态动词'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('学习提示'), findsOneWidget);
    expect(find.textContaining('may have'), findsWidgets);
  });
}

class _GrammarSettingsNotifier extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() {
    return LearningSettingsState.defaults().copyWith(
      translationProvider: 'OpenAI',
      translationApiKey: 'test-key',
      translationBaseUrl: 'https://api.openai.com/v1',
      translationModel: 'gpt-4o-mini',
    );
  }
}
