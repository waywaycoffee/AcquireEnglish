import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../avatar/presentation/avatar_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';

/// Oral wrong-items + due review expressions (ChatterPal learning loop UI).
class LearningReviewScreen extends ConsumerStatefulWidget {
  const LearningReviewScreen({super.key});

  @override
  ConsumerState<LearningReviewScreen> createState() =>
      _LearningReviewScreenState();
}

class _LearningReviewScreenState extends ConsumerState<LearningReviewScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _wrong = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _due = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final List<Map<String, dynamic>> wrong = await api.listWrongItems();
      final List<Map<String, dynamic>> due = await api.listDueLearningReviews();
      if (!mounted) {
        return;
      }
      setState(() {
        _wrong = wrong;
        _due = due;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _complete(String id, {required bool ok}) async {
    try {
      await ref.read(acquireApiClientProvider).completeLearningReview(
        reviewId: id,
        independentOk: ok,
      );
      unawaited(
        ref.read(avatarMeProvider.notifier).earn(
              reason: 'oral_review',
              clientEventId: 'oral_review:$id',
            ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _saveFromWrong(Map<String, dynamic> item) async {
    final String expression =
        '${item['correction'] ?? item['expression'] ?? item['text'] ?? ''}'
            .trim();
    final String quote = '${item['source'] ?? item['quote'] ?? expression}';
    if (expression.isEmpty) {
      return;
    }
    try {
      await ref.read(acquireApiClientProvider).saveReviewExpression(
        expression: expression,
        sourceQuote: quote,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入口语复习')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppDesignTokens.textPrimary,
        title: const Text('口语错题 / 复习'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _reload, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                Text(
                  '待复习 ${_due.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (_due.isEmpty)
                  Text(
                    '暂无待复习表达',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  )
                else
                  ..._due.map((Map<String, dynamic> row) {
                    final String id = '${row['id'] ?? ''}';
                    final String text =
                        '${row['expression'] ?? row['text'] ?? ''}';
                    return Card(
                      child: ListTile(
                        title: Text(text),
                        subtitle: Text('${row['source_quote'] ?? ''}'),
                        trailing: Wrap(
                          spacing: 6,
                          children: <Widget>[
                            TextButton(
                              onPressed: id.isEmpty
                                  ? null
                                  : () => _complete(id, ok: false),
                              child: const Text('还需练'),
                            ),
                            FilledButton(
                              onPressed: id.isEmpty
                                  ? null
                                  : () => _complete(id, ok: true),
                              child: const Text('已掌握'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
                Text(
                  '错题本 ${_wrong.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (_wrong.isEmpty)
                  Text(
                    '暂无错题。口语陪练纠错后会出现在这里。',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  )
                else
                  ..._wrong.map((Map<String, dynamic> row) {
                    final String text =
                        '${row['correction'] ?? row['expression'] ?? row['text'] ?? ''}';
                    return Card(
                      child: ListTile(
                        title: Text(text),
                        subtitle: Text(
                          '${row['source'] ?? row['quote'] ?? ''}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _saveFromWrong(row),
                          child: const Text('加入复习'),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
